# RollCall Backend API (Go)

BEACONTrack yoklama sisteminin Go backend servisi.

## Yapı

```
backend/
├── cmd/
│   └── server/
│       └── main.go                # Uygulama giriş noktası
├── internal/
│   ├── config/
│   │   └── config.go              # Ortam değişkenleri & yapılandırma
│   ├── handler/
│   │   ├── health.go              # Health check endpoint
│   │   └── verification.go        # Yoklama doğrulama endpoint'leri
│   ├── middleware/
│   │   └── auth.go                # Supabase JWT doğrulama middleware
│   ├── model/
│   │   └── verification.go        # Doğrulama veri modelleri
│   ├── repository/
│   │   └── verification.go        # Veritabanı işlemleri
│   └── service/
│       └── verification.go        # İş mantığı katmanı
├── database/
│   └── migrations/
│       └── 001_add_verification_fields.sql
├── config/
│   └── .env.example
├── go.mod
├── go.sum
└── README.md
```

## Kurulum

```bash
cd backend

# Bağımlılıkları yükle
go mod tidy

# .env dosyasını oluştur
cp config/.env.example .env

# Çalıştır
go run cmd/server/main.go
```

## API Endpoint'leri

| Method | Endpoint | Açıklama |
|--------|----------|----------|
| GET | `/api/health` | Health check |
| POST | `/api/v1/verification/verify` | Yoklama doğrulama sonucu kaydet |
| GET | `/api/v1/verification/stats/:course_id` | Ders bazlı doğrulama istatistikleri |
| GET | `/api/v1/verification/logs/:course_id` | Doğrulama logları |

## Ortam Değişkenleri

| Değişken | Açıklama |
|----------|----------|
| `PORT` | Sunucu portu (varsayılan: 8080) |
| `SUPABASE_URL` | Supabase proje URL'si |
| `SUPABASE_ANON_KEY` | Supabase anon key |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase service role key |
| `GIN_MODE` | Gin modu (`debug` / `release`) |
