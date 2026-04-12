# RTM Şablonu ve Örnek

## Boş şablon

```markdown
| REQ-ID | Gereksinim özeti | Senaryo ID | Senaryo adı | Test türü | Öncelik | Durum |
|--------|-----------------|------------|-------------|-----------|---------|-------|
| | | | | | | Planlandı |
```

## Durum değerleri
- `Planlandı` — henüz yazılmadı
- `Yazıldı` — test kodu mevcut
- `Geçti` — son koşumda başarılı
- `Başarısız` — son koşumda hata
- `Bloklu` — bağımlılık nedeniyle çalıştırılamıyor
- `Atlandı` — kapsam dışı bırakıldı (gerekçe ekle)

## Doldurulmuş örnek

| REQ-ID | Gereksinim özeti | Senaryo ID | Senaryo adı | Test türü | Öncelik | Durum |
|--------|-----------------|------------|-------------|-----------|---------|-------|
| REQ-F-001 | Kullanıcı e-posta/şifre ile giriş yapabilmeli | SCN-W-001-H-01 | Geçerli kimlik bilgileriyle giriş | WEB | P0 | Planlandı |
| REQ-F-001 | Kullanıcı e-posta/şifre ile giriş yapabilmeli | SCN-W-001-N-01 | Yanlış şifre ile giriş | WEB | P0 | Planlandı |
| REQ-F-001 | Kullanıcı e-posta/şifre ile giriş yapabilmeli | SCN-W-001-N-02 | 3 başarısız denemede hesap kilitleme | WEB | P1 | Planlandı |
| REQ-F-001 | Kullanıcı e-posta/şifre ile giriş yapabilmeli | SCN-M-001-H-01 | Mobil: geçerli kimlik bilgileriyle giriş | MOB | P0 | Planlandı |
| REQ-F-002 | Oturum 30 dakika sonra otomatik kapanmalı | SCN-W-002-E-01 | 30 dk sonra yeniden yönlendirme | WEB | P1 | Planlandı |
| REQ-NF-001 | Sayfa 3 saniyede yüklenebilmeli | SCN-W-NF-001-H-01 | Ana sayfa yükleme süresi ölçümü | WEB | P2 | Planlandı |
