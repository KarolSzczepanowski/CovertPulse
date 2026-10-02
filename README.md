# CovertPulse: A CPU-Load Modulated Covert Communication Channel in Containerized Environments

![CovertPulse logo](logo.png)

## Author

**Karol Szczepanowski**

- Website: [www.karolszczepanowski.pl](https://www.karolszczepanowski.pl)
- GitHub: [github.com/KarolSzczepanowski](https://github.com/KarolSzczepanowski)

## Opis projektu

**CovertPulse** to eksperymentalny proof of concept pokazujacy ukryty kanal komunikacji oparty o modulacje obciazenia procesora. Nadajnik zamienia tekst na sygnaly Morse'a i reprezentuje je jako kontrolowane skoki uzycia CPU. Odbiornik mierzy obciazenie procesora, rozpoznaje impulsy powyzej zadanego progu i dekoduje odebrany tekst.

Projekt demonstruje, ze nawet w srodowiskach kontenerowych mozna obserwowac wzorce aktywnosci wspoldzielonych zasobow. Nie jest to szybki ani niezawodny kanal transmisji danych; celem jest pokazanie idei, eksperyment badawczy i material edukacyjny.

## Geneza

Idea tego typu ataku pojawila sie po ukonczeniu przeze mnie szkolenia **SANS SEC530**, prowadzonego przez *Ismael Valenzuela*. Szkolenie odbywalo sie w Paryzu w 2026 roku, stad rowniez inspiracja dla `logo.png`.

## Project Description

**CovertPulse** is an experimental proof of concept demonstrating a covert communication channel based on CPU-load modulation. The sender converts text into Morse code and represents it as controlled CPU-load spikes. The receiver samples processor usage, detects pulses above a configured threshold, and decodes the received text.

The project demonstrates that activity patterns on shared resources may be observable even in containerized environments. This is not intended to be a fast or reliable data-transfer mechanism; it is a research-oriented and educational demonstration of the underlying idea.

## Origin

The idea for this type of attack emerged after I completed the **SANS SEC530** training, taught by *Ismael Valenzuela*. The training took place in Paris in 2026, which also inspired the concept behind `logo.png`.

## Components

- `snd_poc.sh` - POC sender. Converts text into Morse code and transmits it through CPU load.
- `rcv_poc.sh` - POC receiver. Samples CPU load and decodes Morse pulses.
- `snd.sh` and `rcv.sh` - active POC copies.
- `run_poc_dockers.sh` - builds and starts two Docker containers: one sender and one receiver.
- `snd_binary_wip.sh` and `rcv_binary_wip.sh` - unfinished binary-transfer experiment, intentionally left as work in progress.
- `logo.png` - project logo.

## Quick Start

Run the containerized POC:

```bash
./run_poc_dockers.sh
```

By default, the sender repeatedly transmits:

```text
Grretings from planet Earth
```

The receiver prints decoded output in the terminal. Stop the demo with `Ctrl+C`.

## Local Usage

Sender:

```bash
echo "SOS" | ./snd_poc.sh
```

Receiver:

```bash
./rcv_poc.sh
```

Useful tuning variables:

```bash
SND_UNIT_S=0.2
SND_SIGNAL_LOAD=99
SND_BACKGROUND_LOAD=0
RCV_INTERVAL_S=0.05
```

## Notes

- The POC uses Morse code, so it is best suited for uppercase letters, digits, spaces, and the supported punctuation set.
- CPU background activity can affect decoding accuracy.
- Timing and threshold values may need adjustment depending on host load, CPU count, and Docker configuration.

## Ethical Use

This project is intended for educational, research, and defensive analysis purposes. Use it only in environments where you have authorization to run CPU-load experiments.
