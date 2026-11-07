from fastapi import FastAPI, Depends, Query, HTTPException
from sqlalchemy import create_engine, Column, Integer, String, Float, ForeignKey, DateTime, func
from sqlalchemy.orm import declarative_base, sessionmaker, Session, relationship
from geoalchemy2 import Geometry
from geoalchemy2.shape import to_shape
from pydantic import BaseModel
from typing import List, Optional
import datetime

DATABASE_URL = "postgresql://postgres:Egeege2022!@localhost:5432/parkiz_db"

engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

class ParkModel(Base):
    __tablename__ = "parks"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(255), nullable=False)
    description = Column(String)
    rating = Column(Float, default=4.5)
    location = Column(Geometry(geometry_type='POINT', srid=4326))
    
    reviews = relationship("ReviewModel", back_populates="park")

class ReviewModel(Base):
    __tablename__ = "reviews"

    id = Column(Integer, primary_key=True, index=True)
    park_id = Column(Integer, ForeignKey("parks.id"))
    user_name = Column(String(100), nullable=False)
    comment = Column(String, nullable=False)
    rating = Column(Float, nullable=False)
    created_at = Column(DateTime, default=datetime.datetime.utcnow)

    park = relationship("ParkModel", back_populates="reviews")

class ReportedReviewModel(Base):
    __tablename__ = "reported_reviews"

    id = Column(Integer, primary_key=True, index=True)
    review_id = Column(Integer, ForeignKey("reviews.id", ondelete="CASCADE"))
    reason = Column(String, nullable=False)
    created_at = Column(DateTime, default=datetime.datetime.utcnow)

class BlockedUserModel(Base):
    __tablename__ = "blocked_users"

    id = Column(Integer, primary_key=True, index=True)
    blocked_user_name = Column(String(100), nullable=False)
    created_at = Column(DateTime, default=datetime.datetime.utcnow)

Base.metadata.create_all(bind=engine)

class ReviewSchema(BaseModel):
    id: int
    user_name: str
    comment: str
    rating: float

    class Config:
        from_attributes = True

class CreateReviewSchema(BaseModel):
    user_name: str
    comment: str
    rating: float

class CreateParkSchema(BaseModel):
    name: str
    description: str
    latitude: float
    longitude: float

class ReportSchema(BaseModel):
    reason: str

class BlockUserSchema(BaseModel):
    user_name: str

class ParkSchema(BaseModel):
    id: str
    name: str
    description: str
    latitude: float
    longitude: float
    rating: float
    distance_meters: Optional[float] = None
    reviews: List[ReviewSchema] = []

    class Config:
        from_attributes = True

app = FastAPI(title="Parkİz PostGIS API")

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

@app.get("/")
def read_root():
    return {"message": "Parkİz PostgreSQL/PostGIS API Çalışıyor"}

@app.get("/api/parks", response_model=List[ParkSchema])
def get_parks(
    lat: Optional[float] = Query(None),
    lng: Optional[float] = Query(None),
    db: Session = Depends(get_db)
):
    # Engellenen kullanıcı adlarını çek
    blocked_names = [b.blocked_user_name for b in db.query(BlockedUserModel).all()]

    parks = db.query(ParkModel).all()
    result = []
    
    for park in parks:
        point = to_shape(park.location)
        dist = None
        
        if lat is not None and lng is not None:
            user_point = f"SRID=4326;POINT({lng} {lat})"
            distance_query = db.query(
                func.ST_Distance(
                    func.ST_Transform(park.location, 3857),
                    func.ST_Transform(func.ST_GeomFromEWKT(user_point), 3857)
                )
            ).scalar()
            dist = round(distance_query, 1) if distance_query else None

        # Engellenmemiş yorumları filtrele
        park_reviews = db.query(ReviewModel).filter(
            ReviewModel.park_id == park.id,
            ReviewModel.user_name.notin_(blocked_names) if blocked_names else True
        ).all()

        result.append(
            ParkSchema(
                id=str(park.id),
                name=park.name,
                description=park.description or "",
                latitude=float(point.y),
                longitude=float(point.x),
                rating=float(park.rating or 4.5),
                distance_meters=dist,
                reviews=[ReviewSchema.from_orm(r) for r in park_reviews]
            )
        )
    return result

@app.post("/api/parks", response_model=ParkSchema)
def create_park(park_data: CreateParkSchema, db: Session = Depends(get_db)):
    point_wkt = f"SRID=4326;POINT({park_data.longitude} {park_data.latitude})"
    new_park = ParkModel(
        name=park_data.name,
        description=park_data.description,
        rating=5.0,
        location=point_wkt
    )
    db.add(new_park)
    db.commit()
    db.refresh(new_park)

    point = to_shape(new_park.location)
    return ParkSchema(
        id=str(new_park.id),
        name=new_park.name,
        description=new_park.description or "",
        latitude=float(point.y),
        longitude=float(point.x),
        rating=5.0,
        distance_meters=0.0,
        reviews=[]
    )

@app.post("/api/parks/{park_id}/reviews", response_model=ReviewSchema)
def add_review(park_id: int, review: CreateReviewSchema, db: Session = Depends(get_db)):
    park = db.query(ParkModel).filter(ParkModel.id == park_id).first()
    if not park:
        raise HTTPException(status_code=404, detail="Park bulunamadı")

    new_review = ReviewModel(
        park_id=park_id,
        user_name=review.user_name,
        comment=review.comment,
        rating=review.rating
    )
    db.add(new_review)
    db.commit()
    db.refresh(new_review)

    avg_rating = db.query(func.avg(ReviewModel.rating)).filter(ReviewModel.park_id == park_id).scalar()
    if avg_rating:
        park.rating = round(avg_rating, 1)
        db.commit()

    return new_review

@app.post("/api/reviews/{review_id}/report")
def report_review(review_id: int, report: ReportSchema, db: Session = Depends(get_db)):
    rev = db.query(ReviewModel).filter(ReviewModel.id == review_id).first()
    if not rev:
        raise HTTPException(status_code=404, detail="Yorum bulunamadı")

    new_report = ReportedReviewModel(
        review_id=review_id,
        reason=report.reason
    )
    db.add(new_report)
    db.commit()
    return {"message": "Yorum başarıyla bildirildi"}

@app.post("/api/users/block")
def block_user(data: BlockUserSchema, db: Session = Depends(get_db)):
    new_block = BlockedUserModel(blocked_user_name=data.user_name)
    db.add(new_block)
    db.commit()
    return {"message": f"{data.user_name} başarıyla engellendi"}