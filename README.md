<p align="center">
  <img src="Design/AppIcon.svg" width="128" alt="AudioShare icon">
</p>

<h1 align="center">AudioShare</h1>

<p align="center">
  Mac'in sesini aynı anda birden fazla kulaklığa ya da hoparlöre gönderen menü çubuğu uygulaması.<br>
  iPhone ve iPad'deki <b>Ses Paylaş</b> özelliğinin macOS karşılığı.
</p>

---

## Ne yapar?

macOS, iki AirPods'u aynı anda dinlemek için hazır bir seçenek sunmuyor. Bunu yapmanın tek yolu Audio MIDI Setup'ta elle "Çoklu Çıkış Aygıtı" oluşturmak. AudioShare bu işi menü çubuğundan tek tıkla yapar:

1. Menü çubuğundaki simgeye tıkla.
2. **Aygıtlar** listesinden sesi göndermek istediğin cihazları seç (en az iki).
3. **Ses Paylaşımı** anahtarını aç.

Paylaşımı kapattığında ses, önceki çıkışına geri döner.

## Özellikler

- **Sadece AirPods değil:** Mac'in gördüğü tüm ses çıkışları listelenir. AirPods, Beats, diğer Bluetooth kulaklıklar ve hoparlörler, dahili hoparlör, USB/HDMI ses aygıtları ve AirPlay bunlara dahil.
- **Bağlı olmayan cihazlar:** Daha önce eşleştirilmiş ama şu an bağlı olmayan Bluetooth cihazları da listede yer alır. Tıklayınca bağlanır ve paylaşıma katılır.
- **Hiç eşleşmemiş cihazlar:** **Yakındaki Aygıtlar → Aygıt Ara** ile eşleştirme modundaki kulaklıklar bulunur, tek tıkla eşleştirilip bağlanır. Arkadaşının AirPods'u için kutunun arkasındaki düğmeyi basılı tutması yeterli.
- **Cihaz başına ses ayarı:** Seçili her cihazın altında kendi ses kaydırıcısı bulunur.
- **Otomatik devam:** Paylaşımdaki bir kulaklığın bağlantısı koparsa (ör. kutusuna konursa) ses diğer cihazlarda çalmaya devam eder ve panelde "… bekleniyor" yazar. Kulaklık geri bağlanınca paylaşım kendiliğinden yeniden başlar. Bir cihazı panelden kendin kaldırırsan ses kalan cihaza geçer. Seçimlerin hatırlanır. Sistem ayarlarından başka bir çıkış seçersen paylaşım kapanır.
- **Native görünüm:** Arayüz macOS'in Bluetooth ve Ses menüleriyle aynı yapıda; açık ve koyu modu destekler.
- **Türkçe ve İngilizce:** Dil, sistem diline göre seçilir.
- Girişte otomatik açılma seçeneği vardır ve Dock'ta simge görünmez.

## Kurulum

Gereksinimler: **macOS 14 (Sonoma) veya üstü** ve Xcode ya da yalnızca Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/2geik/AudioShare.git
cd AudioShare
make install
```

`make install` uygulamayı derler, `/Applications` klasörüne kopyalar ve açar. İlk açılışta macOS Bluetooth izni ister. Kulaklıkların listelenebilmesi için **İzin Ver** demen gerekir.

Diğer komutlar:

| Komut | Açıklama |
| --- | --- |
| `make app` | `build/AudioShare.app` oluşturur |
| `make run` | Derler ve `build/` içinden çalıştırır |
| `make icons` | `Design/*.svg` dosyalarından ikonları yeniden üretir |
| `make clean` | Derleme çıktılarını siler |

## Nasıl çalışır?

AudioShare, Core Audio'nun `AudioHardwareCreateAggregateDevice` API'siyle "stacked" (çoklu çıkış) bir aggregate cihaz oluşturur. Audio MIDI Setup'taki "Çoklu Çıkış Aygıtı" da aynı şeydir. Bu cihaz sistemin varsayılan çıkışı yapılır.

- Saat kaynağı olarak varsa kablolu/dahili bir cihaz seçilir. Diğer cihazlarda kayma düzeltmesi (drift compensation) açık olur.
- Örnekleme hızı tüm cihazların desteklediği ortak değere ayarlanır (genellikle 48 kHz).
- Bluetooth tarafında `IOBluetooth` kullanılır: eşleşmiş cihazların listesi, `IOBluetoothDeviceInquiry` ile tarama, `IOBluetoothDevicePair` ile eşleştirme ve `openConnection` ile bağlanma.
- Uygulama kapanırken oluşturduğu cihazı siler. Çökerse bir sonraki açılışta geride kalan cihazı temizler ve önceki çıkışı geri yükler.

```
Sources/AudioShare/
├── AudioShareApp.swift          Menü çubuğu sahnesi, uygulama yaşam döngüsü
├── AudioShareController.swift   Seçim, paylaşım durumu, cihaz listesinin birleştirilmesi
├── OutputDevice.swift           Cihaz modeli ve ikon (SF Symbol) eşlemesi
├── Audio/                       Core Audio sarmalayıcıları ve çoklu çıkış cihazı
├── Bluetooth/                   Eşleşmiş cihazlar, tarama, eşleştirme, bağlanma
├── Views/                       Menü paneli
└── Support/                     Girişte açılma, Sistem Ayarları bağlantıları
```

## Bilinen sınırlamalar

- **Gecikme farkı:** Bluetooth kulaklıklar kablolu ya da dahili hoparlörlerden yaklaşık 150–250 ms geç çalar ve çoklu çıkış cihazı bunu telafi etmez. İki Bluetooth kulaklık birbirine yakın gecikmeyle çalar, bu yüzden asıl kullanım senaryosu (iki kulaklık) sorunsuzdur.
- **Sistem ses ayarı:** macOS, çoklu çıkış cihazlarında genel ses ayarını desteklemez. Paylaşım açıkken Kontrol Merkezi'ndeki ve menü çubuğundaki ses kaydırıcısı pasif kalır, bunun yerine paneldeki kaydırıcıları kullan. Bunu tamamen çözmek için sanal bir ses sürücüsü ya da "sistem sesi kaydı" izni gerekir, AudioShare bilerek ikisini de kullanmaz.
- **Mikrofon:** Paylaşımdaki bir AirPods'un mikrofonu kullanılırsa (ör. arama sırasında) Bluetooth bağlantısı düşük kaliteli moda geçer.
- **İmza:** Uygulama ad-hoc imzalıdır. Her yeniden derlemeden sonra macOS Bluetooth iznini tekrar sorabilir. Başka bir Mac'e kopyalarsan ilk açılışta *sağ tık → Aç* gerekebilir.
- Bluetooth LE Audio'ya özel (klasik Bluetooth desteklemeyen) cihazlar taramada görünmez. Sistem ayarlarından eşleştirildiklerinde listeye gelirler.

## Geliştirme notları

- Proje Swift Package olarak kurulu. `Scripts/build-app.sh` bundan `.app` paketini üretir, Xcode gerekmez.
- macOS 27 SDK'sında `@State` bir makro ve bu makronun eklentisi yalnızca Xcode ile geliyor. Command Line Tools ile derlenebilmesi için `MenuRowModifier` içinde `State(initialValue:)` açıkça yazıldı.
- Command Line Tools ile derlerken SwiftPM'in varsayılan motoru (Swift Build), binary'ye SDK sürümü olarak minimum hedefi (`sdk 14.0`) yazıyor. AppKit, Liquid Glass görünümünü bu alana bakarak açtığı için `build-app.sh`, `vtool` ile gerçek SDK sürümünü geri yazıyor.
- İkonlar `Design/` klasöründeki SVG dosyalarından `Scripts/render-svg.swift` ile (AppKit'in yerleşik SVG desteği kullanılarak) üretilir.

## Lisans

[MIT](LICENSE)
