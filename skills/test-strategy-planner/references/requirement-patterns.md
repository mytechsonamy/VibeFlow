# Gereksinim Kalıpları ve Senaryo Şablonları

## Yaygın önyüz gereksinim kategorileri

### 1. Kimlik doğrulama (Auth)
**Tipik gereksinimler:** giriş, çıkış, şifre sıfırlama, oturum süresi, rol tabanlı erişim

**Senaryo şablonu:**
```
Senaryo: [Eylem] — [Koşul]
Ön koşul: [Kullanıcı durumu, veri durumu]
Adımlar:
  1. [UI eylemi]
  2. [Beklenen tepki]
Beklenen sonuç: [Görsel/fonksiyonel çıktı]
```

**Edge case'ler:** yanlış şifre (3 deneme kilit), süresi dolmuş token, farklı sekmede çıkış

### 2. Form validasyonu
**Tipik gereksinimler:** zorunlu alanlar, format doğrulama, anlık vs submit-time validasyon

**Edge case'ler:** XSS karakterleri, max uzunluk+1, copy-paste, otomatik doldurma

### 3. Liste ve tablo
**Edge case'ler:** 0 kayıt (empty state), 1 kayıt, sayfalama sınırı, çok uzun metin

### 4. Dosya yükleme
**Edge case'ler:** max boyut+1 byte, izin verilmeyen format, ağ kesilmesi sırasında yükleme

### 5. Gerçek zamanlı güncellemeler (WebSocket/polling)
**Edge case'ler:** bağlantı kesilmesi, yeniden bağlanma, eş zamanlı düzenleme çakışması

---

## Senaryo ID standardı

```
SCN-[PLATFORM]-[REQ-NO]-[TIP]-[NO]

Platform: W=Web, M=Mobil, U=Unit, I=Integration
Tip: H=Happy, E=Edge, N=Negative

Örnek: SCN-W-001-H-01 = Web, REQ-001, Happy path, 1. senaryo
```

---

## Otomatize edilemeyen durumlar (MANUAL işaretle)

- Biyometrik doğrulama (Face ID, Touch ID) — Detox kısmi destek
- Push notification izni popup'ı (iOS native dialog)
- Üçüncü taraf OAuth ekranları (Google, Apple sign-in)
- Gerçek ödeme gateway akışları (sandbox kullan, ama son adım manuel)
- Erişilebilirlik ekran okuyucu deneyimi (NVDA, VoiceOver tam akış)
