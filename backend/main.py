import os
from typing import List, Optional
from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from sqlalchemy import create_engine, Column, Integer, String, Float, Text, text
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session

# 1. Veritabanı Bağlantı Mantığı
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://neondb_owner:npg_PtLV6KX9qbhA@ep-lingering-tree-bakawk4o.c-8.eu-central-1.aws.neon.tech/neondb?sslmode=require"
)

if DATABASE_URL and DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql://", 1)

engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

# 2. Veritabanı Modeli (Park Tablosu)
class ParkModel(Base):
    __tablename__ = "parks"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(255), nullable=False)
    description = Column(Text, nullable=True)
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    rating = Column(Float, default=0.0)

# Veritabanında tabloları otomatik oluştur
Base.metadata.create_all(bind=engine)

# 3. Pydantic Şemaları (API İstek/Yanıt Yapıları)
class ParkCreate(BaseModel):
    name: str
    description: Optional[str] = None
    latitude: float
    longitude: float
    rating: Optional[float] = 0.0

class ParkResponse(ParkCreate):
    id: int

    class Config:
        from_attributes = True

# 4. FastAPI Uygulaması
app = FastAPI(title="Parkiz API", version="1.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Dependency: Her istek için veritabanı oturumu açıp kapatma
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# 5. Endpoint'ler
@app.get("/")
def read_root():
    return {"message": "Parkiz Backend API Live!"}

@app.get("/api/health")
def health_check():
    try:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))
        return {"status": "healthy", "database": "connected"}
    except Exception as e:
        return {"status": "unhealthy", "error": str(e)}

# Tüm Parkları Getir
@app.get("/api/parks", response_model=List[ParkResponse])
def get_parks(db: Session = Depends(get_db)):
    parks = db.query(ParkModel).all()
    return parks

# Yeni Park Ekle
@app.post("/api/parks", response_model=ParkResponse)
def create_park(park: ParkCreate, db: Session = Depends(get_db)):
    db_park = ParkModel(
        name=park.name,
        description=park.description,
        latitude=park.latitude,
        longitude=park.longitude,
        rating=park.rating
    )
    db.add(db_park)
    db.commit()
    db.refresh(db_park)
    return db_park