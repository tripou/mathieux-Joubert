#!/usr/bin/env bash
# Assemble une vidéo (booktrailer ou teaser) à partir d'images fournies dans
# videos/assets/<slug>/ pour un livre de mathieuxjoubert.com.
#
# Usage:
#   ./build.sh <slug> <trailer|teaser> [duree_secondes]
#
# Exemple:
#   ./build.sh echos-de-lumiere trailer 60
#   ./build.sh echos-de-lumiere teaser 18
#
# Prérequis dans videos/assets/<slug>/ :
#   01.jpg, 02.jpg, ... (images/illustrations, dans l'ordre du plan de plans)
#   music.mp3           (optionnel, musique de fond)
#   <mode>.srt          (optionnel, sous-titres synchronisés, ex: trailer.srt)
#   meta.txt            (optionnel, deux lignes: TITLE=... puis CTA=...)
#
# Sortie: videos/output/<slug>-<mode>.mp4

set -euo pipefail

SLUG="${1:?Usage: build.sh <slug> <trailer|teaser> [duree_secondes]}"
MODE="${2:?Usage: build.sh <slug> <trailer|teaser> [duree_secondes]}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="$SCRIPT_DIR/assets/$SLUG"
OUTPUT_DIR="$SCRIPT_DIR/output"
mkdir -p "$OUTPUT_DIR"

if [[ "$MODE" == "trailer" ]]; then
    WIDTH=1920; HEIGHT=1080; DEFAULT_DURATION=60
elif [[ "$MODE" == "teaser" ]]; then
    WIDTH=1080; HEIGHT=1920; DEFAULT_DURATION=17
else
    echo "Mode inconnu: $MODE (attendu: trailer ou teaser)" >&2
    exit 1
fi
DURATION="${3:-$DEFAULT_DURATION}"

shopt -s nullglob
IMAGES=("$ASSETS_DIR"/*.jpg "$ASSETS_DIR"/*.jpeg "$ASSETS_DIR"/*.png)
shopt -u nullglob
IMAGES=($(printf '%s\n' "${IMAGES[@]}" | sort))

if [[ ${#IMAGES[@]} -eq 0 ]]; then
    echo "Aucune image trouvée dans $ASSETS_DIR" >&2
    echo "Dépose tes visuels (01.jpg, 02.jpg, ...) puis relance." >&2
    exit 1
fi

TITLE=""
CTA=""
META_FILE="$ASSETS_DIR/meta.txt"
if [[ -f "$META_FILE" ]]; then
    # shellcheck disable=SC1090
    TITLE=$(grep -m1 '^TITLE=' "$META_FILE" | cut -d= -f2- || true)
    CTA=$(grep -m1 '^CTA=' "$META_FILE" | cut -d= -f2- || true)
fi

NUM_IMAGES=${#IMAGES[@]}
PER_IMAGE=$(awk -v d="$DURATION" -v n="$NUM_IMAGES" 'BEGIN { printf "%.3f", d/n }')

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

# 1. Génère un clip "Ken Burns" (zoom lent) par image, durée égale, format cible.
i=0
CLIP_LIST="$WORKDIR/clips.txt"
: > "$CLIP_LIST"
for IMG in "${IMAGES[@]}"; do
    OUT="$WORKDIR/clip_$i.mp4"
    FRAMES=$(awk -v s="$PER_IMAGE" 'BEGIN { printf "%d", s*25 }')
    ffmpeg -y -loglevel error -loop 1 -i "$IMG" -t "$PER_IMAGE" \
        -vf "scale=${WIDTH}*1.15:${HEIGHT}*1.15,zoompan=z='min(zoom+0.0007,1.15)':d=${FRAMES}:s=${WIDTH}x${HEIGHT}:fps=25,format=yuv420p" \
        -c:v libx264 -pix_fmt yuv420p "$OUT"
    echo "file '$OUT'" >> "$CLIP_LIST"
    i=$((i+1))
done

# 2. Concatène tous les clips.
SLIDESHOW="$WORKDIR/slideshow.mp4"
ffmpeg -y -loglevel error -f concat -safe 0 -i "$CLIP_LIST" -c copy "$SLIDESHOW"

# 3. Ajoute le titre/CTA en surimpression sur les 4 dernières secondes.
TITLED="$WORKDIR/titled.mp4"
FONT="/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
if [[ -n "$TITLE" || -n "$CTA" ]] && [[ -f "$FONT" ]]; then
    FADE_START=$(awk -v d="$DURATION" 'BEGIN { printf "%.2f", d-4 }')
    # Le texte passe par un fichier (textfile=) pour éviter tout problème
    # d'échappement d'apostrophes/deux-points dans le titre ou le CTA.
    TITLE_FILE="$WORKDIR/title.txt"
    CTA_FILE="$WORKDIR/cta.txt"
    printf '%s' "$TITLE" > "$TITLE_FILE"
    printf '%s' "$CTA" > "$CTA_FILE"
    FILTER="drawtext=fontfile=${FONT}:textfile=${TITLE_FILE}:fontcolor=white:fontsize=$((WIDTH/22)):borderw=3:bordercolor=black:x=(w-text_w)/2:y=(h-text_h)/2-40:enable='gte(t\,${FADE_START})'"
    if [[ -n "$CTA" ]]; then
        FILTER="${FILTER},drawtext=fontfile=${FONT}:textfile=${CTA_FILE}:fontcolor=white:fontsize=$((WIDTH/34)):borderw=2:bordercolor=black:x=(w-text_w)/2:y=(h-text_h)/2+40:enable='gte(t\,${FADE_START})'"
    fi
    ffmpeg -y -loglevel error -i "$SLIDESHOW" -vf "$FILTER" -c:a copy "$TITLED"
else
    cp "$SLIDESHOW" "$TITLED"
fi

# 4. Sous-titres optionnels (videos/assets/<slug>/<mode>.srt).
SRT_FILE="$ASSETS_DIR/${MODE}.srt"
CAPTIONED="$WORKDIR/captioned.mp4"
if [[ -f "$SRT_FILE" ]]; then
    ffmpeg -y -loglevel error -i "$TITLED" -vf "subtitles=${SRT_FILE}:force_style='FontName=DejaVu Sans,FontSize=18,PrimaryColour=&HFFFFFF,OutlineColour=&H000000,BorderStyle=1,Outline=2'" -c:a copy "$CAPTIONED"
else
    cp "$TITLED" "$CAPTIONED"
fi

# 5. Musique de fond optionnelle (videos/assets/<slug>/music.mp3), fondue en fin.
MUSIC_FILE="$ASSETS_DIR/music.mp3"
FINAL="$OUTPUT_DIR/${SLUG}-${MODE}.mp4"
if [[ -f "$MUSIC_FILE" ]]; then
    FADE_START=$(awk -v d="$DURATION" 'BEGIN { printf "%.2f", d-2 }')
    ffmpeg -y -loglevel error -i "$CAPTIONED" -i "$MUSIC_FILE" \
        -filter_complex "[1:a]atrim=0:${DURATION},afade=t=out:st=${FADE_START}:d=2,volume=0.6[aout]" \
        -map 0:v -map "[aout]" -c:v copy -shortest "$FINAL"
else
    cp "$CAPTIONED" "$FINAL"
fi

echo "Vidéo générée : $FINAL"
