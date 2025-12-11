-- ---------------------------------------------------------
-- Proje: Ölçeklenebilir Rezervasyon Sistemi Veritabanı
-- Açıklama: Çoklu mekan yönetimi, finansal tutarlılık ve
-- topluluk grupları için tasarladığım ilişkisel veritabanı şeması.
-- ---------------------------------------------------------

CREATE DATABASE IF NOT EXISTS generic_booking_db;
USE generic_booking_db;

-- 1. KULLANICILAR (USERS)
-- Standart son kullanıcıların tutulduğu tablo.
-- E-posta ve kullanıcı adı benzersiz (Unique) olarak ayarlandı.
CREATE TABLE Users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(30) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL, -- Şifreler hashlenmiş olarak saklanacak.
    is_email_verified BOOLEAN DEFAULT FALSE,
    avatar_url VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. HİZMET SAĞLAYICILAR (SERVICE PROVIDERS)
-- Mekan sahiplerinin tutulduğu tablo.
-- Güvenlik gerekçesiyle, admin onayı (is_verified) olmadan işlem yapamazlar.
CREATE TABLE ServiceProviders (
    id INT AUTO_INCREMENT PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    phone_number VARCHAR(11) NOT NULL,
    verification_doc_url VARCHAR(255), -- İşletme belgesi vb. dosya yolu
    is_verified BOOLEAN DEFAULT FALSE, -- Admin onayı durumu (Varsayılan: Beklemede)
    is_phone_verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 3. MEKANLAR (VENUES)
-- Kiralanacak fiziksel alanların özellikleri.
-- Harita işlemleri için hassas enlem/boylam (Decimal) verisi kullanıyorum.
CREATE TABLE Venues (
    id INT AUTO_INCREMENT PRIMARY KEY,
    provider_id INT NOT NULL,
    name VARCHAR(100) NOT NULL,
    city VARCHAR(50) NOT NULL, -- İl bazlı filtreleme için
    district VARCHAR(50) NOT NULL, -- İlçe bazlı filtreleme için
    address TEXT NOT NULL,
    latitude DECIMAL(10, 8), -- Google Maps uyumlu hassas konum
    longitude DECIMAL(11, 8),
    price_per_hour DECIMAL(10, 2) NOT NULL, -- Finansal veri olduğu için Decimal kullandım
    deposit_amount DECIMAL(10, 2) NOT NULL, -- Kapora miktarı
    opening_time TIME NOT NULL,
    closing_time TIME NOT NULL,
    is_active BOOLEAN DEFAULT TRUE, -- Mekan geçici olarak kapatılabilir
    cover_image_url VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    -- Sağlayıcı silinirse ona ait mekanlar da silinsin (Cascade):
    FOREIGN KEY (provider_id) REFERENCES ServiceProviders(id) ON DELETE CASCADE
);

-- 4. MEKAN FOTOĞRAFLARI (VENUE IMAGES)
-- 1NF kuralı gereği, çoklu fotoğrafları ana tablodan ayırdım.
CREATE TABLE VenueImages (
    id INT AUTO_INCREMENT PRIMARY KEY,
    venue_id INT NOT NULL,
    image_url VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (venue_id) REFERENCES Venues(id) ON DELETE CASCADE
);

-- 5. BLOKLU SAATLER (VENUE BLOCKED HOURS)
-- Mekanın haftalık rutinde kapalı olduğu saatleri yönetmek için.
-- Örneğin: "Her Pazartesi 09:00-11:00 arası bakım var."
CREATE TABLE VenueBlockedHours (
    id INT AUTO_INCREMENT PRIMARY KEY,
    venue_id INT NOT NULL,
    day_of_week TINYINT NOT NULL, -- 1: Pazartesi ... 7: Pazar
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    reason VARCHAR(100), -- Örn: "Temizlik", "Özel Ders"
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (venue_id) REFERENCES Venues(id) ON DELETE CASCADE
);

-- 6. TOPLULUK GRUPLARI (COMMUNITY GROUPS)
-- Mekanlara bağlı oluşturulan kullanıcı grupları.
-- İş Kuralı: Bir mekanda aynı isimle iki grup kurulamaz (Composite Unique Key).
CREATE TABLE CommunityGroups (
    id INT AUTO_INCREMENT PRIMARY KEY,
    venue_id INT NOT NULL,
    name VARCHAR(50) NOT NULL,
    avatar_url VARCHAR(255),
    activity_score INT DEFAULT 0, -- Grubun aktiflik puanı
    reputation_score INT DEFAULT 0, -- Grubun itibar puanı
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (venue_id) REFERENCES Venues(id) ON DELETE CASCADE,
    UNIQUE (venue_id, name) -- Veri tutarlılığı kuralı
);

-- 7. GRUP ÜYELERİ (GROUP MEMBERS)
-- Kullanıcılar ve Gruplar arasındaki Many-to-Many ilişkiyi yöneten ara tablo.
-- Rol tabanlı (Admin/Üye) yetkilendirme yapısı içerir.
CREATE TABLE GroupMembers (
    group_id INT NOT NULL,
    user_id INT NOT NULL,
    role ENUM('ADMIN', 'MODERATOR', 'MEMBER') DEFAULT 'MEMBER',
    joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (group_id, user_id), -- Bir kişi aynı gruba iki kez eklenemez
    FOREIGN KEY (group_id) REFERENCES CommunityGroups(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES Users(id) ON DELETE CASCADE
);

-- 8. REZERVASYONLAR (BOOKINGS)
-- Finansal işlem geçmişi.
-- KRİTİK NOT: Snapshot Pattern uygulandı. Mekan fiyatı ileride değişse bile
-- rezervasyon anındaki fiyat (price_at_booking) burada saklanarak geçmiş verinin bozulması önlendi.
CREATE TABLE Bookings (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    venue_id INT NOT NULL,
    start_time DATETIME NOT NULL, -- Tarih ve saat birleşik tutuluyor
    end_time DATETIME NOT NULL,
    status ENUM('PENDING', 'CONFIRMED', 'COMPLETED', 'CANCELLED') DEFAULT 'PENDING',
    price_at_booking DECIMAL(10, 2) NOT NULL, -- Fiyat anlık görüntüsü (Snapshot)
    deposit_paid DECIMAL(10, 2) NOT NULL, -- Ödenen kapora anlık görüntüsü
    contact_phone VARCHAR(11) NOT NULL, -- O işleme özel iletişim numarası
    note TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES Users(id) ON DELETE CASCADE,
    FOREIGN KEY (venue_id) REFERENCES Venues(id) ON DELETE CASCADE
);

-- 9. DEĞERLENDİRMELER (REVIEWS)
-- Sahte yorumları önlemek için sadece rezervasyon kaydı olanlar yorum yapabilir.
-- Unique Constraint ile bir işleme sadece bir yorum yapılması garanti altına alındı.
CREATE TABLE Reviews (
    id INT AUTO_INCREMENT PRIMARY KEY,
    booking_id INT NOT NULL,
    rating TINYINT NOT NULL,
    comment TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (booking_id) REFERENCES Bookings(id) ON DELETE CASCADE,
    UNIQUE (booking_id), -- Mükerrer yorum engelleme
    CHECK (rating >= 1 AND rating <= 5) -- Puan aralığı kontrolü
);
