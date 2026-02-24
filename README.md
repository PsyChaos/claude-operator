# claude-operator

**Runtime profile switching system for `CLAUDE.md`.**

Claude'un davranışını yöneten `CLAUDE.md` dosyasını — versioned, checksummed, imzalanmış ve geri alınabilir biçimde — yönetmek için tasarlanmış, dependency-free bir Bash CLI aracı.

> Claude configuration is infrastructure. It should be versioned, explicit, reproducible, and intentional.

---

## İçindekiler

- [Neden?](#-neden)
- [Özellikler](#-özellikler)
- [Kurulum](#-kurulum)
- [Temel Kullanım](#-temel-kullanım)
- [Conflict Detection](#-conflict-detection)
- [Plugin Mimarisi](#-plugin-mimarisi)
- [Güvenlik](#-güvenlik)
- [Enterprise Mode](#-enterprise-mode)
- [Self-Update](#-self-update)
- [Referans](#-referans)
- [Felsefe](#-felsefe)
- [Katkı](#-katkı)

---

## 🚀 Neden?

Bir projede Claude'un nasıl davranacağını `CLAUDE.md` dosyası belirler. Farklı iş bağlamları, farklı Claude kişilikleri gerektirir:

| Bağlam | İstenen Davranış |
|---|---|
| Production altyapısı | Temkinli, minimal risk, her değişikliği doğrula |
| Hızlı prototipleme | Otonom, clarification loop'suz, iteratif |
| Kompleks özellik geliştirme | Dengeli: production kalitesi + özerk yürütme |

`claude-operator` bu profilleri merkezi olarak yönetir, sürüm pinler, bütünlük doğrular ve projeler arasında deterministik geçiş sağlar.

---

## 📦 Özellikler

### Temel
- **Remote profile fetching** — GitHub üzerinden profile dosyaları çeker
- **Version pinning** — `v1.0.0` gibi belirli bir release'e kilitlenme
- **SHA256 checksum verification** — indirilen her dosya imzalanmış checksumla doğrulanır
- **Atomic writes** — temp dosya + `mv`, `CLAUDE.md`'ye yarım yazma olmaz
- **Strict checksum mode** — `--strict-checksum` ile sha256 tool yoksa hard fail

### Güvenlik
- **GPG signed releases** — tüm release asset'leri CI bot key ile imzalanır
- **Trust key management** — `trust-key` komutu public key'i otomatik indirir ve import eder
- **Signature verification** — `--verify-sig` ile her indirmede GPG doğrulama

### Conflict Detection
- **Unmanaged CLAUDE.md koruması** — mevcut proje dosyasını tespit eder, sorulmadan silmez
- **Interactive prompt** — `[backup / merge / overwrite / abort]` seçenekleri, 10s timeout
- **Backup & restore** — `.claude_backup/` altında max 5 zaman damgalı yedek
- **Sentinel-based composition** — `--merge` ile proje içeriğini koruyarak profil ekler
- **CI-safe defaults** — non-interactive ortamda sessiz backup

### Plugin Mimarisi
- **GitHub repo as registry** — `profiles/*.md` içeren herhangi bir repo plugin olabilir
- **Local override** — `./claude-operator-plugins/` öncelik sırasının başında
- **Versioned plugin fetch** — plugin'ler sürüm pinlenebilir, checksum doğrulanır
- **plugin.json manifest** — opsiyonel metadata desteği

### Enterprise
- **Policy enforcement** — profile whitelist, version pin zorunluluğu, signature zorunluluğu
- **Audit logging** — her işlem ISO8601 timestamp ile loglanır
- **Offline / air-gapped** — local cache'den serve, network çağrısı yok
- **Custom registry** — iç sunucu URL'si ile GitHub yerine internal mirror
- **Shell-sourceable config** — `/etc/claude-operator/enterprise.conf`

### Operasyonel
- **Self-update** — GitHub API üzerinden versiyon karşılaştırır, atomik günceller
- **Global CLI** — `~/.local/bin/claude-operator` ile PATH'e eklenir
- **Makefile integration** — tüm komutlar `make` target'larıyla erişilebilir
- **Dependency-free** — bash + curl + sha256sum/shasum. Başka hiçbir şey gerekmez.

---

## 📁 Depo Yapısı

```
claude-operator/
├── profiles/
│   ├── elite.md                  # Production-grade autonomy + risk calibration
│   ├── high-autonomy.md          # Minimal clarification, fast iteration
│   └── senior-production.md      # Conservative, stability-first
├── operator.sh                   # Ana CLI binary
├── install.sh                    # Installer (local veya global)
├── Makefile                      # Kullanıcı dostu task runner
├── claude-operator.gpg.pub       # CI bot GPG public key
└── .github/workflows/release.yaml
```

---

## 🔧 Kurulum

### Tek satır (en güncel, checksum yok)

```bash
curl -fsSL https://raw.githubusercontent.com/PsyChaos/claude-operator/master/install.sh | bash
```

### Sürüm pinli + SHA256 doğrulama (önerilen)

```bash
curl -fsSL https://raw.githubusercontent.com/PsyChaos/claude-operator/master/install.sh \
  | bash -s -- --version v1.0.0
```

### Sürüm pinli + SHA256 + GPG imza doğrulama (maksimum güvenlik)

```bash
curl -fsSL https://raw.githubusercontent.com/PsyChaos/claude-operator/master/install.sh \
  | bash -s -- --version v1.0.0 --verify-sig
```

### Global kurulum (`claude-operator` komutunu PATH'e ekler)

```bash
# Pinned + imzalı (önerilen)
curl -fsSL https://raw.githubusercontent.com/PsyChaos/claude-operator/master/install.sh \
  | bash -s -- --global --version v1.0.0 --verify-sig
```

`~/.local/bin/claude-operator` olarak kurulur. PATH'te yoksa installer gerekli satırı gösterir.

### Enterprise kurulum

```bash
curl -fsSL https://raw.githubusercontent.com/PsyChaos/claude-operator/master/install.sh \
  | bash -s -- --version v1.0.0 --enterprise
```

Binary'yi kurar ve `~/.config/claude-operator/enterprise.conf` konumuna yorumlu config template'i yazar.

### Kurulum flag'leri

```bash
bash install.sh [seçenekler]
```

| Flag | Kısa | Açıklama |
|------|------|----------|
| `--version v1.0.0` | `-v` | Release'e pin, SHA256 doğrulama etkinleşir |
| `--global` | `-g` | `~/.local/bin/` altına global kurulum |
| `--strict-checksum` | `-s` | SHA256 tool yoksa hard fail (warning yerine) |
| `--verify-sig` | `-S` | GPG imza doğrulama (gpg gerektirir) |
| `--enterprise` | `-e` | Enterprise config template oluştur |
| `--enterprise-config <path>` | | Config template'i özel path'e yaz |

---

## 🧠 Temel Kullanım

### Profil geçişi

```bash
./operator.sh elite
./operator.sh elite v1.0.0          # sürüm pinli
make claude MODE=elite
make claude MODE=elite VERSION=v1.0.0
claude-operator elite               # global kurulum sonrası
```

### Kullanılabilir profiller

| Profil | Karakter |
|--------|----------|
| `elite` | Production kalitesi + otonom yürütme dengesi, risk kalibrasyonlu |
| `high-autonomy` | Minimal clarification, maksimum iterasyon hızı |
| `senior-production` | Temkinli, stability-first, her değişikliği doğrula |

### Runtime flag'leri

```bash
./operator.sh [flag'ler] <mod> [versiyon]
```

| Flag | Env var | Açıklama |
|------|---------|----------|
| `--strict-checksum` | `OPERATOR_STRICT_CHECKSUM=true` | SHA256 tool yoksa abort |
| `--verify-sig` | `OPERATOR_VERIFY_SIG=true` | GPG imza doğrulama |
| `--force` | `CLAUDE_OPERATOR_CONFLICT=force` | Mevcut CLAUDE.md'yi sormadan sil |
| `--backup` | `CLAUDE_OPERATOR_CONFLICT=backup` | Önce yedekle, sonra üzerine yaz |
| `--merge` | `CLAUDE_OPERATOR_CONFLICT=merge` | Proje içeriğini koru, profili ekle |

### Aktif modu göster

```bash
make current
cat .claude_mode           # elite@v1.0.0:backup
```

### Profil listesi

```bash
make list                  # core profiller
./operator.sh plugin list  # core + plugin + local
```

---

## 🛡 Conflict Detection

Mevcut bir projeye `claude-operator` entegre ederken ya da `CLAUDE.md` dosyası zaten varken ne olur?

### Karar ağacı

```
CLAUDE.md var mı?
│
├── YOK → direkt yaz (normal akış)
│
└── VAR
    ├── Operator tarafından mı yönetiliyor?
    │   ├── EVET (sentinel header veya .claude_mode dosyası var)
    │   │   └── --merge flag'i var mı?
    │   │       ├── EVET → sentinel bloğunu güncelle, proje içeriğine dokunma
    │   │       └── HAYIR → direkt üzerine yaz
    │   │
    │   └── HAYIR (unmanaged, el yazısı proje dosyası)
    │       ├── TTY yok (CI/pipe) → sessiz backup, sonra üzerine yaz
    │       ├── CLAUDE_OPERATOR_CONFLICT env var → direkt uygula
    │       └── TTY var → interactive prompt
```

### Interactive prompt

```
Warning: CLAUDE.md exists and is not managed by claude-operator.

  [b] Backup & overwrite  — save to .claude_backup/, apply profile  (default)
  [m] Merge               — keep project content, append profile below
  [o] Overwrite           — replace entirely (current content will be lost)
  [a] Abort               — do nothing

Choice [b/m/o/a] (default: b, auto-selects in 10s):
```

10 saniye içinde seçim yapılmazsa otomatik olarak **backup** seçilir.

### Backup & restore

```bash
# Backup alarak uygula (non-interactive, CI için)
./operator.sh --backup elite v1.0.0
make claude MODE=elite VERSION=v1.0.0 CONFLICT=backup

# Yedekleri listele
./operator.sh restore --list
make restore-list

# Son yedeğe dön
./operator.sh restore
make restore

# Belirli bir yedeğe dön
./operator.sh restore 20260224T103000Z
```

Yedekler `.claude_backup/CLAUDE.md.<timestamp>` formatında saklanır. Maksimum 5 yedek tutulur, eskisi otomatik silinir. `.gitignore`'a otomatik eklenir.

### Composition (--merge)

Proje talimatlarını **korurken** operator profilini `CLAUDE.md`'ye ekler.

```bash
./operator.sh --merge elite v1.0.0
make claude MODE=elite CONFLICT=merge
```

**İlk uygulamada** sentinel bloğu mevcut içeriğin altına eklenir:

```markdown
# Proje talimatları
Bu proje bir TypeScript monorepo'dur. Tüm değişiklikler...

---

<!-- claude-operator:begin elite@v1.0.0 -->
[elite.md içeriği]
<!-- claude-operator:end -->
```

**Sonraki uygulamalarda** sadece sentinel arasındaki operatör bölümü güncellenir — proje içeriğine hiç dokunulmaz. Idempotent'tir.

### Sentinel restore

`--merge` ile yazılmış bir `CLAUDE.md`'den operatör bölümünü kaldırıp proje içeriğini geri almak:

```bash
./operator.sh restore     # sentinel bloğunu siler, proje içeriği kalır
```

Hem sentinel hem backup varsa hangi yöntemle restore edileceği sorulur:

```
Both a sentinel section and a backup are available.

  [s] Remove sentinel   — keep project content, strip operator section
  [b] From backup       — restore last backup
  [a] Abort
```

### `.claude_mode` format

```
elite@v1.0.0:overwrite     # direkt üzerine yazıldı
elite@v1.0.0:backup        # backup alınarak yazıldı
elite@v1.0.0:merge         # sentinel ile composition
```

### CI ortamları için

```bash
# Env var ile prompt atla
CLAUDE_OPERATOR_CONFLICT=backup ./operator.sh elite v1.0.0
CLAUDE_OPERATOR_CONFLICT=force  ./operator.sh elite v1.0.0
CLAUDE_OPERATOR_CONFLICT=merge  ./operator.sh elite v1.0.0
```

---

## 🔌 Plugin Mimarisi

`profiles/*.md` dizinine sahip herhangi bir GitHub reposu plugin registry olarak kullanılabilir.

### Registry ekleme

```bash
./operator.sh plugin add myorg/my-profiles
./operator.sh plugin add myorg/my-profiles v1.0.0   # sürüm pinli + checksum

make plugin-add REGISTRY=myorg/my-profiles
make plugin-add REGISTRY=myorg/my-profiles VERSION=v1.0.0
```

### Profil çözümleme sırası

```
1. ./claude-operator-plugins/<mod>.md      (proje-local, network yok)
2. ~/.config/claude-operator/plugins/...   (cache'li plugin profilleri)
3. github.com/PsyChaos/claude-operator     (core uzak profiller)
```

### Tüm profilleri listele

```bash
./operator.sh plugin list
```

```
Core profiles (PsyChaos/claude-operator):
  elite
  high-autonomy
  senior-production

Plugin: myorg/my-profiles
  fast
  careful

Local (./claude-operator-plugins/):
  custom-mode
```

### Plugin yönetimi

```bash
./operator.sh plugin remove myorg/my-profiles      # kaldır
./operator.sh plugin update                        # tümünü güncelle
./operator.sh plugin update myorg/my-profiles      # tekini güncelle

make plugin-remove REGISTRY=myorg/my-profiles
make plugin-update
make plugin-update REGISTRY=myorg/my-profiles
```

### Local profil override

```bash
mkdir -p claude-operator-plugins
cp my-mode.md claude-operator-plugins/
./operator.sh my-mode          # local dosyayı kullanır, network yok
```

### Plugin manifest (opsiyonel)

Plugin reposunun kök dizininde `plugin.json` varsa okunur:

```json
{
  "name": "my-profiles",
  "description": "Custom Claude profiles for my team",
  "profiles": ["fast", "careful", "debug"]
}
```

**Depolama:**
- Cache: `~/.config/claude-operator/plugins/<owner>__<repo>/`
- Registry listesi: `~/.config/claude-operator/registries.conf`

---

## 🔒 Güvenlik

### SHA256 checksum doğrulama

CI her release'de şu dosyalar için `.sha256` sidecar dosyaları üretir ve release asset'lerine ekler:

- `operator.sh.sha256`
- `install.sh.sha256`
- `profiles/elite.md.sha256`, `profiles/high-autonomy.md.sha256`, `profiles/senior-production.md.sha256`

`--version` ile kurulumda checksum otomatik indirilir ve doğrulanır. Uyuşmazlıkta kurulum durur, temp dosyalar temizlenir.

Sürüm pinli profile fetch'lerde de SHA256 doğrulanır.

`--strict-checksum` ile sha256 tool (sha256sum/shasum) yoksa abort eder. Varsayılan: uyarı ver ve devam et.

### GPG imza doğrulama

Tüm release asset'leri (`operator.sh`, `install.sh`, `profiles/*.md`) CI bot key ile GPG imzalanır. Her release'e `.sig` dosyaları eklenir.

**Başlarken:**

```bash
# Public key'i indir ve keyring'e import et
./operator.sh trust-key

# Artık imza doğrulamayla kullan
./operator.sh --verify-sig elite v1.0.0
./operator.sh --verify-sig update
```

**Key bilgileri:**
- UID: `Claude Operator <psychaos@gmail.com>`
- Public key: `claude-operator.gpg.pub` (repo kökü)
- Local cache: `~/.config/claude-operator/claude-operator.gpg.pub`

### Önerilen kurulum sırası

```bash
# 1. Key'e güven
./operator.sh trust-key

# 2. Sürüm pinli + SHA256 + GPG ile profil uygula
./operator.sh --verify-sig elite v1.0.0

# 3. Güncellemeleri de imzalı al
./operator.sh --verify-sig update
```

---

## 🏢 Enterprise Mode

### Config oluşturma

```bash
bash install.sh --enterprise
make enterprise-config

# Özel path
bash install.sh --enterprise --enterprise-config /etc/claude-operator/enterprise.conf
make enterprise-config ENTERPRISE_CONFIG=/etc/claude-operator/enterprise.conf
```

### Config yükleme sırası (yüksek öncelik en sonda)

```
1. /etc/claude-operator/enterprise.conf     (sistem geneli)
2. ~/.config/claude-operator/enterprise.conf (kullanıcı)
3. CO_* ortam değişkenleri                  (en yüksek öncelik)
```

### Tüm direktifler

```bash
# Enterprise mode'u etkinleştir (aşağıdaki tüm politikaları aktive eder)
ENTERPRISE_MODE=true

# İzin verilen profiller (boşlukla ayrılmış). Boş = hepsi izinli.
ALLOWED_PROFILES="elite senior-production"

# Sürüm zorunluluğu — versiyonsuz çalıştırmayı engeller
REQUIRE_VERSION_PIN=true

# SHA256 tool yoksa hard fail
REQUIRE_CHECKSUM=true

# GPG imza doğrulamayı zorunlu kıl
REQUIRE_SIGNATURE=true

# Audit log (append-only, ISO8601)
AUDIT_LOG=/var/log/claude-operator.log

# İç mirror URL (GitHub yerine)
# Profiles: <URL>/profiles/<mod>.md formatında serve etmeli
PROFILE_REGISTRY_URL=https://internal.corp/claude-profiles

# Güncelleme politikası: "auto" (varsayılan) veya "manual"
UPDATE_POLICY=manual

# Offline mod — sadece cache'den serve et
OFFLINE_MODE=false
```

### Aktif konfigürasyonu göster

```bash
./operator.sh enterprise-status
make enterprise-status
```

### Audit log

```
[2026-02-24T10:30:00Z] user=alice mode=elite version=v1.0.0 outcome=success
[2026-02-24T10:31:05Z] user=bob mode=fast version=unset outcome=failed message=version_pin_required
[2026-02-24T10:32:10Z] user=charlie mode=elite version=v1.0.0 outcome=failed message=profile_not_allowed=fast
```

```bash
make audit-log
```

### Profile cache

Her başarılı fetch sonrası profil `~/.config/claude-operator/cache/<mod>@<ref>.md` olarak cache'lenir.

`OFFLINE_MODE=true` ile network çağrısı yapılmaz, sadece cache kullanılır.

### CI ortam değişkenleri

| Değişken | Örnek | Açıklama |
|---|---|---|
| `CO_ENTERPRISE_MODE` | `true` | Enterprise mode'u aktive et |
| `CO_ALLOWED_PROFILES` | `"elite senior-production"` | İzin verilen profiller |
| `CO_REQUIRE_VERSION_PIN` | `true` | Sürüm zorunluluğu |
| `CO_REQUIRE_CHECKSUM` | `true` | SHA256 zorunluluğu |
| `CO_REQUIRE_SIGNATURE` | `true` | GPG imza zorunluluğu |
| `CO_AUDIT_LOG` | `/var/log/co.log` | Audit log dosyası |
| `CO_PROFILE_REGISTRY_URL` | `https://corp/profiles` | İç mirror |
| `CO_UPDATE_POLICY` | `manual` | Güncelleme politikası |
| `CO_OFFLINE_MODE` | `true` | Offline mod |

---

## 🔄 Self-Update

```bash
./operator.sh update
make update
claude-operator update     # global kurulum sonrası
```

Akış:
1. GitHub Releases API'den en son tag'i çeker (jq gerekmez)
2. Mevcut `OPERATOR_VERSION` ile karşılaştırır
3. Yeni `operator.sh` + `.sha256` indirir
4. SHA256 doğrular
5. `--verify-sig` ile GPG imzasını doğrular
6. `mv` ile atomik olarak kendini günceller

---

## 📋 Referans

### Tüm komutlar

```bash
# Profil geçişi
./operator.sh <mod> [versiyon]
./operator.sh --merge <mod> [versiyon]
./operator.sh --backup <mod> [versiyon]
./operator.sh --force <mod> [versiyon]

# Geri yükleme
./operator.sh restore
./operator.sh restore --list
./operator.sh restore <timestamp>

# Plugin yönetimi
./operator.sh plugin add <owner/repo> [versiyon]
./operator.sh plugin list
./operator.sh plugin remove <owner/repo>
./operator.sh plugin update [<owner/repo>]

# Güvenlik
./operator.sh trust-key
./operator.sh --verify-sig <mod> [versiyon]

# Güncelleme
./operator.sh update

# Enterprise
./operator.sh enterprise-status

# Yardım
./operator.sh
```

### Tüm Makefile target'ları

```bash
make claude MODE=<profil> [VERSION=<tag>] [CONFLICT=merge|backup|force]
make list
make current
make update
make restore
make restore-list
make install-global
make plugin-add REGISTRY=<owner/repo> [VERSION=<tag>]
make plugin-list
make plugin-remove REGISTRY=<owner/repo>
make plugin-update [REGISTRY=<owner/repo>]
make enterprise-config [ENTERPRISE_CONFIG=<path>]
make enterprise-status
make audit-log
make help
```

### Önemli dosya ve dizinler

| Yol | Açıklama |
|---|---|
| `./CLAUDE.md` | Aktif Claude konfigürasyonu (operator tarafından yönetilir) |
| `./.claude_mode` | Aktif mod ve yazma yöntemi (`elite@v1.0.0:merge`) |
| `./.claude_backup/` | Timestamp'li CLAUDE.md yedekleri (max 5) |
| `./claude-operator-plugins/` | Proje-local profil override dizini |
| `~/.config/claude-operator/` | Kullanıcı konfigürasyonu ve cache |
| `~/.config/claude-operator/registries.conf` | Kayıtlı plugin registry'leri |
| `~/.config/claude-operator/plugins/` | İndirilen plugin profilleri |
| `~/.config/claude-operator/cache/` | Profile cache (offline mode için) |
| `~/.config/claude-operator/enterprise.conf` | Kullanıcı enterprise konfigürasyonu |
| `/etc/claude-operator/enterprise.conf` | Sistem geneli enterprise konfigürasyonu |

### .gitignore

`claude-operator` aşağıdaki satırları `.gitignore`'a otomatik ekler (yoksa):

```
CLAUDE.md
.claude_mode
.claude_backup/
```

---

## 🏷 Versiyonlama

Proje **Semantic Versioning** kullanır.

| Bump | Neden |
|------|-------|
| MAJOR | Breaking davranış değişikliği |
| MINOR | Yeni profil veya özellik |
| PATCH | Düzeltme / dokümantasyon güncellemesi |

---

## 🧪 Felsefe

Claude konfigürasyonu bir altyapı bileşenidir.

Tıpkı Dockerfile, terraform state veya CI pipeline gibi:

- **Versioned** — hangi davranışın ne zaman etkin olduğu izlenebilir
- **Explicit** — varsayılan değil, bilinçli seçim
- **Reproducible** — aynı versiyon, aynı davranış — her ortamda, her zaman
- **Intentional** — her profil geçişi bir karardır, bir kaza değil

---

## 🤝 Katkı

### Yeni profil eklerken

- Mevcut profillerin yapısal tutarlılığını koru
- Davranış felsefesini açıkça belgele
- README'yi güncelle
- MINOR versiyon çıkar

### Yeni özellik eklerken

- Dependency-free kal: bash + curl + POSIX araçları
- Makefile target ekle
- `--help` çıktısını ve README referans bölümünü güncelle
- `bash -n` ile syntax doğrula

---

## 📜 Lisans

MIT

---

## 👤 Yazar

PsyChaos
