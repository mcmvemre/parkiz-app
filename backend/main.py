import os
from typing import List, Optional
from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from sqlalchemy import create_engine, Column, Integer, String, Float, Text, Boolean, ForeignKey, text
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session, relationship

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://neondb_owner:npg_PtLV6KX9qbhA@ep-lingering-tree-bakawk4o.c-8.eu-central-1.aws.neon.tech/neondb?sslmode=require"
)

if DATABASE_URL and DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql://", 1)

engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

class ParkModel(Base):
    __tablename__ = "parks"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(255), nullable=False)
    description = Column(Text, nullable=True)
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    rating = Column(Float, default=0.0)
    has_accessible_ramp = Column(Boolean, default=False)
    has_disabled_swing = Column(Boolean, default=False)
    image_url = Column(Text, nullable=True)

    comments = relationship("CommentModel", back_populates="park", cascade="all, delete-orphan")

class CommentModel(Base):
    __tablename__ = "comments"

    id = Column(Integer, primary_key=True, index=True)
    park_id = Column(Integer, ForeignKey("parks.id"), nullable=False)
    author_name = Column(String(100), default="Anonim Veli")
    text = Column(Text, nullable=False)
    rating = Column(Float, default=5.0)

    park = relationship("ParkModel", back_populates="comments")

Base.metadata.create_all(bind=engine)

class CommentCreate(BaseModel):
    author_name: Optional[str] = "Anonim Veli"
    text: str
    rating: Optional[float] = 5.0

class CommentResponse(CommentCreate):
    id: int
    park_id: int

    class Config:
        from_attributes = True

class ParkCreate(BaseModel):
    name: str
    description: Optional[str] = None
    latitude: float
    longitude: float
    rating: Optional[float] = 0.0
    has_accessible_ramp: Optional[bool] = False
    has_disabled_swing: Optional[bool] = False
    image_url: Optional[str] = None

class ParkResponse(ParkCreate):
    id: int
    comments: List[CommentResponse] = []

    class Config:
        from_attributes = True

class NearbyParkRequest(BaseModel):
    latitude: float
    longitude: float
    radius_km: Optional[float] = 5.0

class ImageUploadRequest(BaseModel):
    image_url: str

app = FastAPI(title="Parkiz API", version="1.5.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

@app.get("/")
def read_root():
    return {"message": "Parkiz Backend Live!"}

@app.get("/api/parks", response_model=List[ParkResponse])
def get_parks(db: Session = Depends(get_db)):
    return db.query(ParkModel).all()

@app.post("/api/parks", response_model=ParkResponse)
def create_park(park: ParkCreate, db: Session = Depends(get_db)):
    db_park = ParkModel(**park.model_dump())
    db.add(db_park)
    db.commit()
    db.refresh(db_park)
    return db_park

@app.post("/api/parks/{park_id}/comments", response_model=CommentResponse)
def add_comment(park_id: int, comment: CommentCreate, db: Session = Depends(get_db)):
    db_park = db.query(ParkModel).filter(ParkModel.id == park_id).first()
    if not db_park:
        raise HTTPException(status_code=404, detail="Park bulunamadı")
    
    db_comment = CommentModel(park_id=park_id, **comment.model_dump())
    db.add(db_comment)
    db.commit()
    db.refresh(db_comment)
    return db_comment

@app.post("/api/parks/nearby", response_model=List[ParkResponse])
def get_nearby_parks(req: NearbyParkRequest, db: Session = Depends(get_db)):
    raw_query = text("""
        SELECT *, (
            6371 * acos(
                cos(radians(:lat)) * cos(radians(latitude)) *
                cos(radians(longitude) - radians(:lng)) +
                sin(radians(:lat)) * sin(radians(latitude))
            )
        ) AS distance
        FROM parks
        WHERE (
            6371 * acos(
                cos(radians(:lat)) * cos(radians(latitude)) *
                cos(radians(longitude) - radians(:lng)) +
                sin(radians(:lat)) * sin(radians(latitude))
            )
        ) <= :radius
        ORDER BY distance ASC;
    """)
    
    result = db.execute(raw_query, {"lat": req.latitude, "lng": req.longitude, "radius": req.radius_km})
    parks = result.fetchall()
    
    park_ids = [p.id for p in parks]
    if not park_ids:
        return []
    return db.query(ParkModel).filter(ParkModel.id.in_(park_ids)).all()

@app.post("/api/parks/{park_id}/upload-image")
def update_park_image(park_id: int, req: ImageUploadRequest, db: Session = Depends(get_db)):
    db_park = db.query(ParkModel).filter(ParkModel.id == park_id).first()
    if not db_park:
        raise HTTPException(status_code=404, detail="Park bulunamadı")

    db_park.image_url = req.image_url
    db.commit()
    db.refresh(db_park)
    return {"message": "Resim güncellendi", "image_url": db_park.image_url}