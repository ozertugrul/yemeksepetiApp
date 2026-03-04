# Varsayılan Çalışma Talimatı (YemeksepetiApp)

Bu depo için Copilot çalışma varsayılanları:

1. Geliştirme deposu olarak **daima** bu yolu kullan:
   - `/root/ertu/yemeksepetiApp`

2. Docker/local PostgreSQL işlemlerinde öncelik:
   - `backend/docker-compose.yml`
   - Local DB portu: `54322`
   - Aktif PostgreSQL verisini gerekiyorsa `backups/` altına SQL + dump olarak dışa aktar.

3. Firebase bağımlılığı:
   - Firebase SDK/import/dependency ekleme.
   - Firebase’e bağlı eski kod tespit edilirse SQL/JWT tabanlı akışa taşı.

4. Build ve simülatör hedefi (macOS ortamında):
   - Build task dosyası: `/Users/ertu-mac/Desktop/yemeksepetiApp/.vscode/tasks.json`
   - Patch sonrası build kökü: `/Users/ertu-mac/Desktop/yemeksepetiApp/yemeksepetiApp`

5. Repo senkronizasyon politikası:
   - Kaynak depo: uzak Linux çalışma alanı (`/root/ertu/yemeksepetiApp`)
   - Hedef depo: macOS local kopya (`/Users/ertu-mac/Desktop/yemeksepetiApp`)
   - Senkronizasyon yöntemi: `rsync`

6. İş akışı sırası:
   - Önce kod patch
   - Sonra rsync ile macOS local’e senkronizasyon
   - Sonra simülatör build
   - Build hatası varsa kod düzeltmesini yine geliştirme deposunda yap

> Not: Linux ortamı macOS yoluna doğrudan erişemiyorsa rsync ve simülatör build adımları macOS makinede çalıştırılmalıdır.
