import os
import hashlib
import datetime
from typing import List, Optional
from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from pydantic import BaseModel
from sqlalchemy import create_engine, Column, Integer, String, Float, Text, Boolean, ForeignKey, text
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session, relationship
import jwt

SECRET_KEY = os.getenv("SECRET_KEY", "parkiz_super_secret_key_2026")
ALGORITHM = "HS256"

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://neondb_owner:npg_PtLV6KX9qbhA@ep-lingering-tree-bakawk4o.c-8.eu-central-1.aws.neon.tech/neondb?sslmode=require"
)

if DATABASE_URL and DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql://", 1)

engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/login", optional=True)

class UserModel(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    full_name = Column(String(100), nullable=False)
    email = Column(String(255), unique=True, index=True, nullable=False)
    hashed_password = Column(String(255), nullable=False)

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

# Tabloları oluştur/güncelle
try:
    Base.metadata.create_all(bind=engine)
except Exception:
    pass

class UserRegister(BaseModel):
    full_name: str
    email: str
    password: str

class UserResponse(BaseModel):
    id: int
    full_name: str
    email: str

    class Config:
        from_attributes = True

class Token(BaseModel):
    access_token: str
    token_type: str
    user: UserResponse

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

app = FastAPI(title="Parkiz API", version="2.2.0")

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

def hash_pwd(password: str) -> str:
    return hashlib.sha256(password.encode()).hexdigest()

def create_access_token(data: dict):
    to_encode = data.copy()
    expire = datetime.datetime.utcnow() + datetime.timedelta(days=7)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

def get_current_user_optional(token: Optional[str] = Depends(oauth2_scheme), db: Session = Depends(get_db)) -> Optional[UserModel]:
    if not token:
        return None
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        email: str = payload.get("sub")
        if email is None:
            return None
        return db.query(UserModel).filter(UserModel.email == email).first()
    except Exception:
        return None

@app.get("/")
def read_root():
    return {"message": "Parkiz API Live!"}

@app.post("/api/auth/register", response_model=UserResponse)
def register(user_data: UserRegister, db: Session = Depends(get_db)):
    existing_user = db.query(UserModel).filter(UserModel.email == user_data.email).first()
    if existing_user:
        raise HTTPException(status_code=400, detail="Bu e-posta adresi zaten kayıtlı.")
    
    new_user = UserModel(
        full_name=user_data.full_name,
        email=user_data.email,
        hashed_password=hash_pwd(user_data.password)
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    return new_user

@app.post("/api/auth/login", response_model=Token)
def login(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    user = db.query(UserModel).filter(UserModel.email == form_data.username).first()
    if not user or user.hashed_password != hash_pwd(form_data.password):
        raise HTTPException(status_code=400, detail="E-posta veya şifre hatalı.")
    
    access_token = create_access_token(data={"sub": user.email})
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "user": user
    }

@app.get("/api/parks", response_model=List[ParkResponse])
def get_parks(db: Session = Depends(get_db)):
    try:
        return db.query(ParkModel).all()
    except Exception as e:
        print("Hata get_parks:", e)
        return []

@app.post("/api/parks", response_model=ParkResponse)
def create_park(park: ParkCreate, db: Session = Depends(get_db)):
    db_park = ParkModel(**park.model_dump())
    db.add(db_park)
    db.commit()
    db.refresh(db_park)
    return db_park

@app.post("/api/parks/{park_id}/comments", response_model=CommentResponse)
def add_comment(
    park_id: int, 
    comment: CommentCreate, 
    db: Session = Depends(get_db),
    current_user: Optional[UserModel] = Depends(get_current_user_optional)
):
    db_park = db.query(ParkModel).filter(ParkModel.id == park_id).first()
    if not db_park:
        raise HTTPException(status_code=404, detail="Park bulunamadı")
    
    author = current_user.full_name if current_user else comment.author_name
    db_comment = CommentModel(park_id=park_id, author_name=author, text=comment.text, rating=comment.rating)
    db.add(db_comment)
    db.commit()
    db.refresh(db_comment)
    return db_comment

@app.post("/api/parks/nearby", response_model=List[ParkResponse])
def get_nearby_parks(req: NearbyParkRequest, db: Session = Depends(get_db)):
    try:
        raw_query = text("""
            SELECT id FROM parks
            WHERE (
                6371 * acos(
                    cos(radians(:lat)) * cos(radians(latitude)) *
                    cos(radians(longitude) - radians(:lng)) +
                    sin(radians(:lat)) * sin(radians(latitude))
                )
            ) <= :radius
        """)
        result = db.execute(raw_query, {"lat": req.latitude, "lng": req.longitude, "radius": req.radius_km})
        park_ids = [row[0] for row in result.fetchall()]
        if not park_ids:
            return []
        return db.query(ParkModel).filter(ParkModel.id.in_(park_ids)).all()
    except Exception as e:
        print("Hata get_nearby_parks:", e)
        return db.query(ParkModel).all()

@app.post("/api/parks/{park_id}/upload-image")
def update_park_image(park_id: int, req: ImageUploadRequest, db: Session = Depends(get_db)):
    db_park = db.query(ParkModel).filter(ParkModel.id == park_id).first()
    if not db_park:
        raise HTTPException(status_code=404, detail="Park bulunamadı")

    db_park.image_url = req.image_url
    db.commit()
    db.refresh(db_park)
    return {"message": "Resim güncellendi", "image_url": db_park.image_url}