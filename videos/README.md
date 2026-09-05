# Vidéos promotionnelles — mathieuxjoubert.com

Scripts et pipeline pour créer des booktrailers et teasers pour les livres
présentés sur le site, à publier sur la chaîne YouTube et le compte X.

## Contenu

- `scripts/` — un script (voix off + plan de plans) par livre et par format :
  - `<slug>-trailer.md` : vidéo longue (16:9, ~50-60s) pour YouTube.
  - `<slug>-teaser.md` : vidéo courte (9:16, ~15-18s) pour Shorts/Reels/X.
- `assets/<slug>/` — dossier où déposer tes visuels pour chaque livre :
  - `01.jpg`, `02.jpg`, … : images/illustrations dans l'ordre du plan de plans.
  - `music.mp3` (optionnel) : musique de fond.
  - `trailer.srt` / `teaser.srt` (optionnel) : sous-titres synchronisés.
  - `meta.txt` : `TITLE=` et `CTA=` déjà pré-remplis pour chaque livre.
- `build.sh` — assemble une vidéo mp4 à partir des images (effet Ken Burns),
  ajoute le titre/CTA en fin de vidéo, mixe la musique et burn les sous-titres
  si présents.
- `output/` — vidéos générées (non versionnées, voir `.gitignore`).

## Livres couverts

| Slug | Titre |
|------|-------|
| `echos-de-lumiere` | Les Derniers Échos de Lumière |
| `origine-guidee` | L'Origine Guidée |
| `silence` | Sous le poids du silence |
| `levain` | Le Levain |
| `antlia` | Constellation d'Antlia |
| `dotty` | Les Aventures magiques de Dotty |
| `arc-en-ciel` | Les 4 Aventuriers de la Planète Arc-en-ciel |

## Utilisation

1. Lis le script du livre concerné dans `scripts/` pour connaître les visuels
   à préparer (photos, illustrations, images générées, extraits animés...).
2. Dépose ces visuels dans `assets/<slug>/`, numérotés dans l'ordre
   (`01.jpg`, `02.jpg`, ...). Ajoute `music.mp3` si tu as une musique.
3. Génère la vidéo :

   ```bash
   ./build.sh <slug> trailer     # vidéo longue 16:9
   ./build.sh <slug> teaser      # vidéo courte verticale 9:16
   ```

   Tu peux forcer une durée précise (en secondes) en 3ᵉ argument :
   `./build.sh echos-de-lumiere trailer 45`.

4. Le résultat est dans `output/<slug>-<mode>.mp4`, prêt à uploader.

## Prérequis

`ffmpeg` doit être installé (`apt-get install ffmpeg`). Le script a été testé
avec ffmpeg 6.1.
