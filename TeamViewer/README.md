# TeamViewer – lozinka + allowlista

`tv-setup.ps1` na računalu s već instaliranim TeamViewerom (full verzija, 15+):

1. uvozi allowlistu i sigurnosne postavke iz `.tvopt` exporta (samo HKLM dio),
2. postavlja lozinku za nenadzirani pristup,
3. provjerava da je allowlista uključena.

Log: `C:\ProgramData\Akdamar\tv-setup.log`

> **`.tvopt` datoteka NIJE u ovom repozitoriju** (repo je javni). Drži je na internom shareu / u RMM-u i kopiraj je na klijent zajedno sa skriptom.

## Pokretanje

1. Kopiraj `tv-setup.ps1` i `.tvopt` u istu mapu na klijentu, npr. `C:\Temp\`.
2. Otvori **Windows PowerShell kao Administrator** (Start → desni klik na *Windows PowerShell* → *Run as administrator*).
3. Pokreni:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Temp\tv-setup.ps1 -Password "NovaLozinka123!"
```

Ako `.tvopt` nije u istoj mapi kao skripta, dodaj `-SettingsFile "C:\Put\do\datoteke.tvopt"`.

Preko RMM-a: pokreni kao **SYSTEM**. Ako agent pokrene 32-bitni PowerShell, skripta se sama prebaci u 64-bitni.

## Izlazni kodovi

| Kod | Značenje |
|-----|----------|
| 0 | OK |
| 1 | Nije pokrenuto kao admin |
| 2 | TeamViewer nije instaliran |
| 3 | `.tvopt` ne postoji ili nije u registry formatu |
| 4 | `reg import` nije uspio |
| 5 | `setpassword` nije uspio |
| 6 | Allowlista nije uključena nakon uvoza |

## Kako napraviti novi `.tvopt`

Na referentnom računalu: TeamViewer → *Extras → Options → Security → Block and Allowlist* → podesi listu, zatim *Advanced → Export options to a \*.tvopt file*.
Preporuka: prije exporta uključi zaštitu opcija lozinkom (*Advanced → Options protected by password*), da korisnik ne može sam maknuti allowlistu.

## Napomena

Lozinka u komandnoj liniji ostaje vidljiva u RMM logu i PowerShell povijesti. Nakon deploya je promijeni ako je log dostupan trećima.
