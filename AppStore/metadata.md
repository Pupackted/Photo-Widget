# App Store Connect — listing and submission notes

Character limits are App Store Connect's. Everything here is a draft to edit.

## Before you submit

- [ ] **Pick a unique name.** "Photo Widget" is almost certainly taken. The name shown under the icon stays "Photo Widget" (the bundle display name), so only the store name needs to be unique.
- [ ] **Host the privacy policy** (`privacy-policy.md`, e.g. on GitHub Pages or Notion) and paste the URL into App Store Connect → App Privacy → Privacy Policy URL. Optionally set `AppInfo.privacyPolicyURL` so Settings links to it.
- [ ] **Support URL** is required. A simple page or the same site as the policy works. Set `AppInfo.supportEmail` to show "Contact Support" in Settings.
- [ ] After the app record exists, set `AppInfo.appStoreID` so "Rate Photo Widget" opens the review page directly.
- [ ] Screenshots: iPhone 6.9" (1320 × 2868) and, because iPad is supported, iPad 13" (2064 × 2752).
- [ ] Add Indonesian as a localization in App Store Connect and paste the Indonesian copy below.

## Name & subtitle

| Field | Limit | Suggestion |
|---|---|---|
| Name | 30 | Framed: Photo Widgets |
| Name (alt.) | 30 | Keepsake – Photo Widget |
| Subtitle | 30 | Photos on your Home Screen |
| Subtitle (id) | 30 | Foto favorit di Layar Utama |

## Promotional text (170)

**en:** Put your favorite photos on your Home Screen — one at a time or as a collage, framed like a print, changing through the day. Private by design: nothing leaves your phone.

**id:** Pasang foto favorit di Layar Utama — satu per satu atau kolase, terbingkai seperti foto cetak, berganti sepanjang hari. Privat: tak ada yang keluar dari ponsel Anda.

## Description

**en**

Turn your favorite photos into beautiful Home Screen widgets.

Pick a few photos, and Photo Widget frames them for every widget size — faces and subjects stay in view automatically. Then make it yours:

• Rotating photos — up to 50 per widget, changing every 15 minutes, hourly or daily, in order or shuffled
• Album sync — keep a widget in step with any album, including Favorites
• On This Day — photos taken on this day in past years, fresh every morning
• Collages — show one, two or four photos at once
• Frames — full bleed, a soft border, or an instant-film print with a caption
• Filters — Vivid, Golden, Coastal, Film, Mono and more, with adjustable intensity
• Captions — your own words, a caption for each photo, the date it was taken, "3 years ago", or a day counter like "120 days together" or "12 days until Bali"
• Smart framing — pinch and drag to fine-tune any photo at any size
• Tap to shuffle — make a widget show the next photo when you tap it
• Shuffle from Control Center or with Siri
• Works on iPhone and iPad, in StandBy, and on tinted Home Screens

Private by design. Photo Widget uses the system photo picker, so it only sees the photos you choose — library access is asked for only if you sync an album or turn on On This Day. There are no accounts, no ads and no tracking, and your photos never leave your device.

**id**

Ubah foto favorit Anda menjadi widget Layar Utama yang indah.

Pilih beberapa foto, dan Photo Widget membingkainya untuk setiap ukuran widget — wajah dan objek utama otomatis tetap terlihat. Lalu sesuaikan:

• Foto yang berganti — hingga 50 foto per widget, berganti tiap 15 menit, tiap jam, atau harian, berurutan atau acak
• Sinkron album — widget selalu mengikuti album pilihan Anda, termasuk Favorit
• Hari Ini Dulu — foto yang diambil pada tanggal ini di tahun-tahun sebelumnya, diperbarui setiap pagi
• Kolase — tampilkan satu, dua, atau empat foto sekaligus
• Bingkai — penuh, bingkai lembut, atau gaya foto instan dengan keterangan
• Filter — Cerah, Keemasan, Pesisir, Film, Mono, dan lainnya, dengan intensitas yang bisa diatur
• Keterangan — tulisan Anda sendiri, keterangan per foto, tanggal foto diambil, "3 tahun lalu", atau hitungan hari seperti "120 hari bersama" atau "12 hari menuju Bali"
• Pembingkaian pintar — cubit dan seret untuk menyesuaikan foto di setiap ukuran
• Ketuk untuk berganti — widget menampilkan foto berikutnya saat diketuk
• Acak dari Pusat Kontrol atau dengan Siri
• Berfungsi di iPhone dan iPad, di StandBy, dan di Layar Utama yang diwarnai

Privat sejak awal. Photo Widget menggunakan pemilih foto bawaan sistem, jadi hanya melihat foto yang Anda pilih — akses perpustakaan hanya diminta jika Anda menyinkronkan album atau menyalakan Hari Ini Dulu. Tanpa akun, tanpa iklan, tanpa pelacakan, dan foto Anda tidak pernah keluar dari perangkat.

## Keywords (100, comma-separated, no spaces after commas)

**en:** `photo,widget,home screen,collage,frame,polaroid,countdown,days,shuffle,album,picture,memories`

**id:** `foto,widget,layar utama,kolase,bingkai,polaroid,hitung mundur,hari,kenangan,album,gambar,acak`

## Categories

- Primary: Photo & Video
- Secondary: Lifestyle

## Age rating

Answer "None" / "No" to every question → **4+**.

## App Privacy ("nutrition label")

**Data Not Collected.** The app has no network code, no analytics and no third-party SDKs. Photo library access (for album sync and On This Day) stays on the device, which doesn't count as collection. The bundled privacy manifests (`PrivacyInfo.xcprivacy` in the app and the widget) declare only `UserDefaults` use for the app's own settings and the App Group shared with the widget.

## Export compliance

`ITSAppUsesNonExemptEncryption = NO` is set in the build, so App Store Connect won't ask on each upload.

## Notes for App Review

> No account or login is needed. Photo Widget uses the system photo picker (PHPicker) by default, which needs no permission. Photo library access is requested only when the user chooses "Sync an Album" or "On This Day" (New Widget menu, or Timing → Photos from in the editor); it's used on-device to pick photos for those widgets. A daily background app refresh keeps On This Day current.
>
> To review: open the app, tap Get Started, choose a few photos, and adjust the widget in the editor. Then long-press the Home Screen → Edit → Add Widget → search "Photo Widget" and add any size. Long-press the placed widget → Edit Widget to pick which of your widgets it shows. Control Center's "Shuffle Photos" control (iOS 18+) and the Siri phrase "Shuffle Photo Widget" advance every widget to its next photo.

## What's New (1.0)

First release.
