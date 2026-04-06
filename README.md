Glavni sadrzaj je u folderu `Sistemi_projekat/`:

- `design/` sadrzi VHDL modele sistema
- `scripts/` sadrzi Tcl skripte za otvaranje projekta i demonstraciju otpornosti na greske
- `constraint/` sadrzi XDC fajl
- `files/` sadrzi ulazne, koeficijentske i referentne txt fajlove
- `sim/` sadrzi testbench i pratece simulacione fajlove
- `DSONG projekat - E180_2024.pdf` je finalna PDF verzija izvjestaja za predaju

Za otvaranje projekta pokrenuti `scripts/run.tcl`, koji otvara ili pravi projekat i uvezuje design, simulation i constraint fajlove.

Poslije toga:

- `Run Simulation -> Run Behavioral Simulation`
- `Run Synthesis`
- `Run Implementation`

Demonstracija otpornosti na greske:

```tcl
source C:/putanja/do/repoa/Sistemi_projekat/scripts/force_fault.tcl
source C:/putanja/do/repoa/Sistemi_projekat/scripts/force_fault_campaign.tcl
```

`force_fault.tcl` pokazuje ponasanje sistema pri jednoj ubacenoj gresci, a `force_fault_campaign.tcl` sluzi za vise uzastopnih gresaka i pracenje trosenja rezervi `K`.

Analiza za razlicite `N,K` kombinacije:

```tcl
source C:/putanja/do/repoa/Sistemi_projekat/scripts/analysis_nk_flow.tcl
```
