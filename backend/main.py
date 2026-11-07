import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import create_engine, text
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

# 1. DATABASE_URL Okuma Mantığı (Neon Veritabanı Adresi ile Fallback)
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://neondb_owner:npg_PtLV6KX9qbhA@ep-lingering-tree-bakawk4o.c-8.eu-central-1.aws.neon.tech/neondb?sslmode=require"
)

# Render / SQLAlchemy Uyum Sertleştirmesi (postgres:// -> postgresql:// dönüştürmesi)
if DATABASE_URL and DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql://", 1)

# 2. SQLAlchemy Bağlantı Motoru ve Oturum Kurulumu
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

# 3. FastAPI Uygulaması Oluşturma
app = FastAPI(
    title="Parkiz API",
    description="Parkiz Backend API with PostGIS Support",
    version="1.0.0"
)

# 4. CORS Ayarları (Flutter Erişimi İçin)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 5. Bağlantı Testi ve Ana Endpoint'ler
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

@app.get("/api/parks")
def get_parks():
    # Geçici statik liste (Veritabanı tablolarınız hazır olana kadar Flutter testi için)
    return [
        {
            "id": 1,
            "name": "Örnek Çocuk Parkı",
            "latitude": 41.0082,
            "longitude": 28.9784,
            "rating": 4.5
        }
    ]