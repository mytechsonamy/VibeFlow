# Risk Bazlı Önceliklendirme Rehberi

## P0 — Blocker kriterleri
Aşağıdakilerden herhangi biri varsa P0:
- Para, ödeme veya finansal işlem içeriyor
- Kullanıcı verisi kalıcı olarak kaybedilebilir
- Güvenlik açığı (auth bypass, veri sızıntısı)
- Uygulamanın açılmasını veya temel navigasyonu engelliyor
- Tüm kullanıcı tiplerini etkiliyor (admin dahil)

## P1 — Kritik kriterleri
- Ana kullanıcı akışının bir adımı tamamlanamıyor
- Hata mesajı gösterilmiyor, kullanıcı neden başarısız olduğunu bilemiyor
- Veri kayıt edilemiyor (ama kurtarılabilir)
- Rolün ana fonksiyonu çalışmıyor

## P2 — Önemli kriterleri
- Workaround mevcut ama zahmetli
- Belirli bir cihaz/tarayıcıda sorun var
- Edge case kullanıcıları etkiliyor (<10% kullanım senaryosu)
- UI bozuk ama fonksiyon çalışıyor

## P3 — Düşük kriterleri
- Kozmetik (renk, spacing, font)
- Nadiren kullanılan özellik
- "Nice to have" iyileştirme

---

## UAT geçiş eşiği (önerilen)

| Öncelik | Geçiş şartı |
|---------|-------------|
| P0 | %100 geçmeli, sıfır açık |
| P1 | %100 geçmeli, sıfır açık |
| P2 | %90 geçmeli, açıklar kayıt altında |
| P3 | Zorunlu değil, sonraki sprint |

Eşiği değiştirmek için kullanıcıyla mutabık kal ve `test-strategy.md` dosyasına yaz.
