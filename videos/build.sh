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
#   narration.mp3       (optionnel, voix off/lecture d'extrait, pleine piste ;
#                        si présent et qu'aucune durée n'est passée en 3e
#                        argument, la durée de la vidéo s'aligne dessus)
#   music.mp3           (optionnel, musique de fond, en sourdine sous narration.mp3)
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
NARRATION_FILE="$ASSETS_DIR/narration.mp3"
if [[ -n "${3:-}" ]]; then
    DURATION="$3"
elif [[ -f "$NARRATION_FILE" ]]; then
    DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$NARRATION_FILE")
    DURATION=$(awk -v d="$DURATION" 'BEGIN { printf "%.2f", d }')
else
    DURATION="$DEFAULT_DURATION"
fi

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

# Toile de fond agrandie (15%) sur laquelle zoompan effectue le Ken Burns,
# recadrée depuis le centre (force_original_aspect_ratio=increase + crop)
# pour ne jamais déformer une image dont le ratio diffère du format cible.
BIGW=$(awk -v w="$WIDTH" 'BEGIN { v=int(w*1.15); if (v%2!=0) v++; print v }')
BIGH=$(awk -v h="$HEIGHT" 'BEGIN { v=int(h*1.15); if (v%2!=0) v++; print v }')

# 1. Génère un clip "Ken Burns" (zoom lent, centré) par image, durée égale.
i=0
CLIP_LIST="$WORKDIR/clips.txt"
: > "$CLIP_LIST"
for IMG in "${IMAGES[@]}"; do
    OUT="$WORKDIR/clip_$i.mp4"
    FRAMES=$(awk -v s="$PER_IMAGE" 'BEGIN { printf "%d", s*25 }')
    ffmpeg -y -loglevel error -loop 1 -i "$IMG" -t "$PER_IMAGE" \
        -vf "scale=${BIGW}:${BIGH}:force_original_aspect_ratio=increase,crop=${BIGW}:${BIGH},zoompan=z='min(zoom+0.0007,1.15)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=${FRAMES}:s=${WIDTH}x${HEIGHT}:fps=25,format=yuv420p" \
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
# Fond opaque (BorderStyle=3/BackColour) + police plus grande et remontée
# (MarginV) pour rester lisible sur un fond chargé et hors des zones d'UI
# (boutons, pseudo) des plateformes verticales.
SRT_FILE="$ASSETS_DIR/${MODE}.srt"
CAPTIONED="$WORKDIR/captioned.mp4"
if [[ -f "$SRT_FILE" ]]; then
    SUB_FONTSIZE=$((WIDTH/24))
    ffmpeg -y -loglevel error -i "$TITLED" -vf "subtitles=${SRT_FILE}:force_style='FontName=DejaVu Sans,Bold=1,FontSize=${SUB_FONTSIZE},PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,BackColour=&HA0000000,BorderStyle=3,Outline=1,Shadow=0,MarginV=90'" -c:a copy "$CAPTIONED"
else
    cp "$TITLED" "$CAPTIONED"
fi

# 5. Piste audio : narration.mp3 (pleine voix, prioritaire) mixée avec
# music.mp3 en sourdine si les deux sont présents, sinon l'un ou l'autre.
MUSIC_FILE="$ASSETS_DIR/music.mp3"
FINAL="$OUTPUT_DIR/${SLUG}-${MODE}.mp4"
FADE_START=$(awk -v d="$DURATION" 'BEGIN { v=d-1; if (v<0) v=0; printf "%.2f", v }')
if [[ -f "$NARRATION_FILE" && -f "$MUSIC_FILE" ]]; then
    ffmpeg -y -loglevel error -i "$CAPTIONED" -i "$NARRATION_FILE" -i "$MUSIC_FILE" \
        -filter_complex "[1:a]atrim=0:${DURATION},afade=t=out:st=${FADE_START}:d=1[narr];[2:a]atrim=0:${DURATION},volume=0.15,afade=t=out:st=${FADE_START}:d=1[bed];[narr][bed]amix=inputs=2:duration=first:dropout_transition=0[aout]" \
        -map 0:v -map "[aout]" -c:v copy -shortest "$FINAL"
elif [[ -f "$NARRATION_FILE" ]]; then
    ffmpeg -y -loglevel error -i "$CAPTIONED" -i "$NARRATION_FILE" \
        -filter_complex "[1:a]atrim=0:${DURATION},afade=t=out:st=${FADE_START}:d=1[aout]" \
        -map 0:v -map "[aout]" -c:v copy -shortest "$FINAL"
elif [[ -f "$MUSIC_FILE" ]]; then
    ffmpeg -y -loglevel error -i "$CAPTIONED" -i "$MUSIC_FILE" \
        -filter_complex "[1:a]atrim=0:${DURATION},afade=t=out:st=${FADE_START}:d=1,volume=0.6[aout]" \
        -map 0:v -map "[aout]" -c:v copy -shortest "$FINAL"
else
    cp "$CAPTIONED" "$FINAL"
fi

echo "Vidéo générée : $FINAL"
