# Next Episode

Aplicație Flutter pentru urmărirea serialelor și filmelor. TVmaze și TMDB sunt module de metadate. Identitatea catalogului și datele utilizatorului aparțin aplicației. Interfața folosește o temă întunecată futuristă, cu accente cyan/violet, carduri pentru titluri și episoade, postere rotunjite și progres vizual. Tema comună se află în `lib/ui/app_theme.dart`.

## Rulare

```powershell
./start.ps1
```



Scriptul citește `.env` și pornește aplicația Windows cu date reale (`DEMO=false`). Fără configurație, un profil nou folosește TVmaze, fără token. SDK-ul local este `.tools/flutter` (ignorat de Git). Alternativ: `flutter pub get`, apoi `flutter run -d windows`. Hot reload nu recitește valorile de compilare.

Windows necesită Visual Studio C++ și Developer Mode. Android necesită Android SDK; iOS necesită macOS, Xcode și semnare. Versiunea locală verificată: Flutter 3.47.2 / Dart 3.13.2.

## Schimbarea administrativă a sursei

Furnizorul nu poate fi ales din interfața publică. Nu există selector sau confirmare de migrare. Temporar, pentru testare la cererea administratorului, căutarea globală afișează „Caută seriale · TVmaze” sau „Caută seriale și filme · TMDB”, folosind furnizorul activ confirmat. Această etichetă de diagnostic va fi eliminată după testare. Pagina Despre conține atribuirea statică pentru ambele servicii.

Pentru o versiune nouă, configurația administratorului este:

```dotenv
CONTENT_PROVIDER=tvmaze
CONTENT_GENERATION=1
CONTENT_CONFIG_URL=
TMDB_TOKEN=
```

Pentru trecerea la TMDB: setează `CONTENT_PROVIDER=tmdb`, completează `TMDB_TOKEN` cu Read Access Token/Bearer și crește `CONTENT_GENERATION` (de exemplu la 2). Distribuie noul build. `CATALOG_PROVIDER` este acceptat doar ca alias de compatibilitate atunci când `CONTENT_PROVIDER` lipsește. Fișierul `.env` existent nu este rescris automat.

La prima sincronizare, configurația este pregătită administrativ în fundal. Furnizorul confirmat în SQLite rămâne activ până la commit. Simpla construire a unui router cu alt provider nu modifică biblioteca. O generație mai veche sau egală nu poate anula o configurație deja confirmată. La revenire se folosește tot o generație mai mare.

O eroare de rețea/autentificare în timpul pregătirii lasă migrarea `pending`; sincronizarea următoare reia operațiunea. Un titlu negăsit sau ambiguu devine `review`, își păstrează cache-ul și marcările, iar celelalte titluri pot fi migrate. Raportul final va fi `committed_with_review`. Actualizarea titlurilor încă neasociate poate folosi sursa lor anterioară; interfața nu expune această diferență.

Tokenul nu se pune în Git. Valorile incluse într-un client compilat nu sunt secrete de server; un backend poate păstra tokenul și furniza metadatele prin proxy.

## Operațiuni administrative explicite

Utilitarul operează pe baza SQLite indicată, niciodată pe o bază dedusă sau creată accidental. Închide aplicația pentru operarea offline. Baza aplicației este `next_episode.sqlite` în directorul returnat de `getApplicationSupportDirectory()`; calea depinde de platformă. Administratorul poate executa utilitarul pentru fiecare bază de profil administrată.

```powershell
# Pregătire sau reluare; nicio modificare a catalogului activ.
.\.tools\flutter\bin\dart.bat run tool/catalog_admin.dart prepare --database C:\cale\next_episode.sqlite --deployment tmdb-2027 --target tmdb --generation 2

# Raport: titluri ready/review/pending, motiv, ID extern și încredere.
.\.tools\flutter\bin\dart.bat run tool/catalog_admin.dart report --database C:\cale\next_episode.sqlite --deployment tmdb-2027

# Activare atomică a tuturor titlurilor pregătite și a configurației.
.\.tools\flutter\bin\dart.bat run tool/catalog_admin.dart activate --database C:\cale\next_episode.sqlite --deployment tmdb-2027

# Revenire la metadatele precedente; păstrează acțiunile utilizatorului de după migrare.
.\.tools\flutter\bin\dart.bat run tool/catalog_admin.dart rollback --database C:\cale\next_episode.sqlite --deployment tmdb-2027 --generation 3
```

`prepare` citește implicit `.env`; `--env PATH` poate indica alt fișier. Nu tipărește tokenuri. Pentru o asociere de titlu verificată manual, administratorul poate furniza `--matches matches.json`, unde documentul este, de exemplu, `{"tv:1":108978}`: cheia este titlul intern, valoarea este ID-ul extern de destinație. Aprobarea titlului nu ocolește verificarea episoadelor. După un commit cu titluri în review, o corecție se publică printr-un deployment și o generație noi.

Nu există încă editor administrativ pentru remapări speciale de episoade sau sezoane. Aceste conflicte rămân conservator în review, cu datele precedente intacte; nu se remapează automat progresul după titlu sau dată.

## Configurație globală de la un backend

`CONTENT_CONFIG_URL` poate indica un endpoint HTTPS administrat central. Acesta returnează exclusiv:

```json
{"provider":"tmdb","deploymentId":"tmdb-2027","generation":2,"phase":"prepared"}
```

`prepared` permite pregătirea fără activare. După verificarea disponibilității, backendul publică aceeași revizie cu `phase: "committed"`. Un manifest nu acceptă procente, liste de utilizatori sau alte câmpuri de segmentare. Erorile de descărcare, configurația invalidă și reviziile vechi păstrează configurația confirmată anterior.

`ContentConfigurationSource.ready(report)` este punctul de integrare pentru confirmările către backend. Implementarea HTTPS actuală doar citește manifestul; nu există încă server, autentificare de administrator, colectare centrală a confirmărilor sau baze cloud. Endpointul global trebuie să livreze aceeași revizie tuturor clienților. Pentru o lansare coordonată în producție, backendul trebuie să gestioneze pregătirea și commit-ul global. Clienții offline păstrează ultima revizie validă: activarea simultană pe toate dispozitivele nu poate fi garantată de această aplicație locală.

## Identitate, date personale și metadate

| Categorie | Stocare |
| --- | --- |
| Titluri interne | `catalog_titles`: tip + ID intern; metadate curente în `data` |
| Sezoane interne | `internal_seasons`: serial intern + ID intern + număr sezon |
| Episoade interne | `internal_episodes`: ID intern, relație cu sezonul și cheie logică unică |
| Corespondențe externe | `entity_links`: cheie internă, tip, provider, provider ID, IMDb, TVDB, ultima verificare, încredere |
| Aliasuri cu unicitate | `catalog_refs`, `episode_refs`: legături simultane TVmaze/TMDB |
| Date ale utilizatorului | `library`, `watched`, `preferences`, `user_history`; chei interne și date ale acțiunilor |
| Metadate offline | `cache`; niciun marcaj văzut în payload-urile furnizorilor |
| Administrare | `content_state`, `admin_migrations`, `admin_migration_items`, `admin_conflicts` |

Cheia logică a unui episod obișnuit este `internalShowId:seasonNumber:episodeNumber`. `S02E03` păstrează ID-ul intern indiferent de ID-ul extern, traducerea titlului sau schimbarea datei. ID-urile sezoanelor și episoadelor sunt locale; `source_id` reține ID-ul extern. Specialele fără numerotare sigură sunt tratate separat.

Schema v3 migrează automat bazele v1/v2, păstrând ID-urile existente, cache-ul, preferințele și marcările, inclusiv rezervările pentru titluri eliminate. Istoricul nou înregistrează adăugări/eliminări și marcări/anulări; nu inventează acțiuni istorice care nu au fost înregistrate de versiunile vechi.

Asocierea titlului folosește IMDb/TVDB. Dacă acestea lipsesc, sunt necesare împreună titlul original, anul, țara și rețeaua, cu un singur candidat sigur. Contradicțiile între ID-uri externe, duplicatele, episoadele lipsă sau renumerotate devin conflicte administrative. Metadatele noi și episoadele/sezoanele noi sunt adăugate fără schimbarea identităților existente.

Pregătirea este persistentă și reluabilă. Activarea verifică dacă biblioteca sau metadatele s-au schimbat între timp și solicită intern o nouă pregătire dacă este necesar. Backupul de metadate și pointerul activ se salvează în aceeași tranzacție cu actualizările. Datele utilizatorului sunt comparate înainte/după tranzacție. Rollbackul păstrează aliasurile ambelor servicii și episoadele noi, astfel încât acțiunile efectuate după migrare să nu fie pierdute.

## Module

- `lib/domain/catalog_provider.dart`: contractul pentru surse externe.
- `lib/data/catalog/tvmaze_provider.dart`, `tmdb_provider.dart`: adaptoare HTTP și normalizare.
- `lib/data/catalog/internal_catalog.dart`: graful intern, corespondențe și verificări.
- `lib/data/catalog/catalog_router.dart`: citire prin configurația confirmată.
- `lib/data/catalog/admin_migration.dart`: pregătire, activare, raport, rollback.
- `lib/data/catalog/content_configuration.dart`: configurație de build sau manifest global.
- `tool/catalog_admin.dart`: utilitar administrativ pentru SQLite.
- `lib/data/repositories.dart`: cache, bibliotecă, progres, sincronizare.
- `lib/application/providers.dart`, `lib/ui/`: Riverpod și interfață.

Un modul nou implementează `CatalogProvider` și se înregistrează în `configuredModules()` și în utilitarul administrativ. Routerul normalizează identitățile înainte ca datele să ajungă în interfață.

## Funcții păstrate

Bibliotecă persistentă cu sortare și filtre; căutare globală și locală; detalii de serial, film, sezon și episod; marcări individuale sau pe sezon; eliminare cu confirmare și păstrarea progresului pentru readăugare; De văzut și Calendar.

Progresul exclude specialele și episoadele viitoare/fără dată. Marcările și datele lor rămân identice la schimbarea sursei. Procentul calculat rămâne identic pentru aceeași listă de episoade lansate; adăugarea firească a unor episoade lansate poate modifica numitorul. Sincronizarea rulează automat la pornire, la revenirea în prim-plan și la fiecare 30 de minute cât aplicația este activă, inclusiv pentru date actualizate recent. Interfața nu mai are butoane de actualizare manuală; cache-ul rămâne disponibil în timpul sincronizării și offline. Erorile publice sunt generale; detaliile operaționale sunt păstrate administrativ.

TVmaze nu are catalog de filme sau traduceri ro-RO. Căutarea de filme poate întoarce zero rezultate; filmele deja salvate rămân disponibile. Interfața este în engleză. TMDB solicită metadate în en-US; datele deja salvate se înlocuiesc la următoarea sincronizare reușită. Filtrele și sortările salvate cu etichetele românești rămân compatibile. Nicio valoare lipsă nu este inventată. Datele de difuzare reprezintă lansarea originală, nu neapărat disponibilitatea în România.

## Settings și alerte locale

Butonul Settings înlocuiește informațiile din dreapta sus. Afișează numărul de seriale/filme din bibliotecă, preferințe persistente pentru alerte, un interval de 0–23 ore și 0–59 minute Before/After the show, ora locală de rezervă pentru lansări fără oră, Terms of Use, Privacy Policy și versiunea reală din pachet. Creditele sunt în About & data credits. Documentele sunt drafturi pentru editorul temporar Test; contactul și textele finale trebuie completate înainte de publicare.

Alertele folosesc flutter_local_notifications pe iOS/Android și cer permisiune numai la activare. Off anulează notificările programate. Modificările bibliotecii/progresului și sincronizarea replanifică cele mai apropiate 60 de episoade nevizionate, fără speciale sau date necunoscute. Before/After este relativ la începutul episodului, nu la sfârșit. TVmaze air_stamp este folosit când există; datele fără oră folosesc ora aleasă (implicit 20:00). Programarea folosește instanți UTC; orele locale de rezervă sunt recalculate la următoarea sincronizare după schimbarea fusului orar. Android folosește alarme inexacte care permit idle, fără permisiune specială de alarmă exactă. Sistemul poate întârzia livrarea. Nu există serviciu push sau proces de sincronizare permanent: coada se reumple când aplicația este deschisă. Windows afișează setările dar comutatorul de alerte este indisponibil.

Configurare adăugată: receivers Android pentru programare/reboot, POST_NOTIFICATIONS, desugaring Java și delegate iOS. Noile dependențe cer `flutter pub get` și repornirea completă a aplicației. `pubspec.lock` nu a fost regenerat: rezolvarea dependențelor, testele și buildurile sunt blocate de limita de utilizare raportată anterior de auto-review. Nu a fost confirmată livrarea pe telefoane. Testele `test/alerts_test.dart` acoperă offseturi, trecerea peste miezul nopții, date fără oră și persistența preferințelor. Validarea pe dispozitive trebuie să includă accept/refuz permisiuni, fundal, restart Android, dezactivare, schimbare offset și marcarea/eliminarea unui episod.

## Detalii în panouri suprapuse

Serialele se deschid într-un panou modal redimensionabil, cu imagine mare, titlu, metadate și descriere. Taburile Episodes și Details folosesc același header. Sezoanele sunt selectate direct în Episodes, cu marcări individuale și pe sezon. Episodul se deschide într-un al doilea panou; X sau glisarea în jos la începutul listei îl închide și păstrează starea panoului serialului.

Details afișează network, created by și distribuție cu fotografii și personaje. TMDB încarcă și videos/watch providers; trailerul se deschide extern, iar serviciile din toate regiunile sunt reunite într-o listă alfabetică fără duplicate sau separare după plată, cu atribuire JustWatch și linkul TMDB. TVmaze încarcă fotografiile distribuției și creatorii din crew; trailerul și disponibilitatea regională fără date sunt indicate ca indisponibile. Aceste schimbări și testul de navigare adaptat nu au fost încă executate în Flutter din cauza blocajului anterior de utilizare.

## Search: căutare automată și titluri populare

Căutarea pornește de la 3 caractere, după 350 ms fără tastare. Răspunsurile căutărilor anterioare sunt ignorate. La prima deschidere a paginii Search și când textul are mai puțin de 3 caractere, sunt afișate titlurile populare. TVmaze afișează seriale; TMDB combină seriale și filme, cu badge pentru fiecare tip.

TMDB folosește `/tv/popular` și `/movie/popular`. TVmaze nu are un endpoint public pentru popularitate: modulul citește primele 20 de seriale din [lista publică TVmaze](https://www.tvmaze.com/shows), apoi încarcă metadatele prin API. Această parte depinde de structura HTML a listei. Routerul păstrează rezultatele populare 12 ore și folosește cache-ul expirat dacă rețeaua eșuează. Prima încărcare TVmaze poate dura mai mult pentru a spația cererile API.

Teste adăugate în `test/popular_test.dart` și `test/state_test.dart` pentru furnizori, pragul de 3 caractere, debounce și ignorarea răspunsurilor vechi. Aceste modificări nu au fost compilate sau testate automat încă, din cauza limitei de utilizare raportate de verificarea automată a aprobărilor. Validarea istorică de mai jos precedă aceste modificări.

## Verificare

```powershell
.\.tools\flutter\bin\dart.bat format --output=none --set-exit-if-changed lib test tool
.\.tools\flutter\bin\flutter.bat analyze
.\.tools\flutter\bin\flutter.bat test
.\.tools\flutter\bin\flutter.bat test test/tvmaze_live_test.dart --dart-define=LIVE_TVMAZE=true
.\.tools\flutter\bin\flutter.bat build windows --debug
```

`test/administrative_migration_test.dart` demonstrează Reacher fictiv cu patru sezoane și 32 de episoade, cinci văzute, transfer TVmaze → mock TMDB, același progres 5/32, aceleași identități și date personale, metadate actualizate și ambele seturi de ID-uri externe. Include serial negăsit, ambiguitate, renumerotare, episod lipsă/nou, conflict, pregătire/activare întrerupte, reluare după redeschiderea bazei, rollback și manifest pregătit/confirmat. Fixture-ul nu afirmă numărul real actual de sezoane Reacher.

Testele obișnuite folosesc HTTP controlat și SQLite real. Testul live TVmaze este opt-in, fără token. Demo: `flutter run -d windows --dart-define=DEMO=true`, bază în memorie cu date fictive.

Limite rămase: design final, iconuri, autentificare/cloud, notificări, editor administrativ de conflicte de episoade, builduri mobile și validare TMDB cu token real. Imaginile nu sunt garantate offline; nu există refresh OS în fundal sau cache eviction.

Referințe: [TVmaze API și atribuire](https://www.tvmaze.com/api), [TMDB Find](https://developer.themoviedb.org/reference/find-by-id).

This product uses the TMDB API but is not endorsed or certified by TMDB.

### Validare executată la 2026-09-08

- `dart format`: 30 de fișiere, fără modificări necesare.
- `flutter analyze`: fără probleme.
- `flutter test --dart-define=LIVE_TVMAZE=true`: **52 de teste trecute**, inclusiv TVmaze real.
- `flutter build windows --debug`: build Windows reușit.
- Utilitarul `catalog_admin.dart --help` pornește direct cu Dart.
- Testele TMDB ale migrării folosesc un mock; tokenul real și buildurile mobile nu au fost validate aici.




## Calendar: istoric și lansări viitoare

Calendarul folosește postere pentru serialele din bibliotecă. Nu există selector. Calendarul se deschide la săptămâna curentă; scroll în sus arată trecutul grupat pe luni (de exemplu January 2022 și February 2022), iar scroll în jos arată săptămânile viitoare și Date TBA separat. Today derulează înapoi la săptămâna curentă, chiar dacă aceasta nu are episoade. Fiecare poster reprezintă un episod și deschide direct detaliile lui la apăsare, fără listă intermediară. Episoadele sunt ordonate după data lansării în fiecare lună sau săptămână. Bifa apare numai dacă episodul a fost văzut. Sunt incluse și episoadele văzute în istoric; specialele rămân în detaliile sezonului 0. Implementare: lib/domain/schedule.dart și lib/ui/calendar.dart. Teste adăugate în test/schedule_test.dart; rularea lor rămâne de făcut după deblocarea limitei de utilizare.
