#!/usr/bin/bash

set -e

function show_help() {
    echo "
 censorSHIT - Simple script to avoid hash-based recognition systems on messaging apps
 ===
 -v
    Specify the logger's verbosity level.
    Can be stacked.

 -h | --help
    Show this help message and quit

 -l | --logger
    Specify the method to log message to the console.
    Options are: echo, gum, quiet

 -n | --noise
    Modify the volume of the noise track overlayed on the original audio.
    Default is: 0.2

 -p | --pixels
    Modify the number of pixels overlayed on the original video.
    Default is: 1

 -o | --out
    Specify the name of to use for the output file.
    Default is: out.mp4

 [ POSITIONAL ]
    Specify the video to modify
    "
}

function log_echo() {
    LVL=$(echo "$2" | sed 's/.*|//g')
    COL=$(echo "$2" | sed 's/|.*//g')
    if [[ $LVL -gt $VERBOSE ]]; then
        return
    fi
    echo "($COL) [$(date)] $1"
}

function log_gum() {
    LVL=$(echo "$2" | sed 's/.*|//g')
    COL=$(echo "$2" | sed 's/|.*//g')
    if [[ $LVL -gt $VERBOSE ]]; then
        return
    fi
    echo '{{Color "'$COL'" " (*)"}}{{ Color "'$S_C_MUTE'" " ['$(date)']" }}' $1 | gum format -t template
}

LOG="log_gum"

function require_gum() {
    if ! type "gum" > /dev/null; then echo "!!! Missing recommended dependency: gum !!!" && LOG="log_echo"; fi
}

function require() {
    if ! type "$1" > /dev/null; then echo "!!! Missing required dependency: $1 !!!" && exit 2; fi
}

require_gum
require bc
require openssl
require ffmpeg
require mogrify

S_C_MUTE="8"
C_ERR="1|0"
C_INFO="10|0"
C_WARN="11|0"
C_DEBUG="4|1"
C_TRACE="5|2"

FFMPEG="ffmpeg -loglevel quiet"

function ceil() {
    echo "define ceil (x) {if (x<0) {return x/1} \
        else {if (scale(x)==0) {return x} \
        else {return x/1 + 1 }}} ; ceil($1)" | bc
}

function random_hex() {
    echo -n "#$(openssl rand -hex 3)"
}

function random_area() {
    W=$(($(echo $1 | sed 's/x.*//g') - 1))
    H=$(($(echo $1 | sed 's/.*x//g') - 1))
    X=$(echo $(($RANDOM % $W)))
    Y=$(echo $(($RANDOM % $H)))
    echo -n "$X,$Y $(($X + 1)),$(($Y + 1))"
}

POSITIONAL_ARGS=()
NOISEVOL=0.2
PIXELSNUM=1
OUTFILE="out.mp4"
LOGGER="gum"

shopt -s extglob
while [[ $# -gt 0 ]]; do
    case $1 in
        -v*)
            VERBOSE=$(($(echo "$1" | wc -c) - 2))
            shift
            ;;
        -h | --help)
            show_help
            exit 0
            ;;
        -l | --logger)
            LOGGER=$2
            case $LOGGER in
                "gum")
                    LOG="log_gum"
                    ;;
                "echo")
                    LOG="log_echo"
                    ;;
                "quiet")
                    LOG=":"
                    ;;
                *)
                    $LOG "Invalid logger: $LOGGER" $C_ERR
                    exit 1
                    ;;
            esac
            shift
            shift
            ;;
        -n | --noise)
            NOISEVOL=$2
            shift
            shift
            ;;
        -p | --pixels)
            PIXELSNUM=$2
            shift
            shift
            ;;
        -o | --out)
            OUTFILE=$2
            shift
            shift
            ;;
        -* | --*)
            $LOG "Invalid option: $1" $C_ERR
            exit 1
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

set -- "${POSITIONAL_ARGS[@]}"
trap '$LOG "$BASH_COMMAND" $C_TRACE' DEBUG

INVID="$1"
if [ -z $INVID ]; then
    $LOG "Invalid input file" $C_ERR
    exit 1
fi
TMP="tmp.$(openssl rand -hex 6)/"
$LOG "VERBOSE = $VERBOSE" $C_DEBUG
$LOG "TMP = $TMP" $C_DEBUG
$LOG "NOISEVOL = $NOISEVOL" $C_DEBUG
$LOG "PIXELSNUM = $PIXELSNUM" $C_DEBUG
$LOG "LOGGER = $LOGGER" $C_DEBUG
$LOG "VIDEO = $INVID" $C_DEBUG
$LOG "OUTFILE = $OUTFILE" $C_DEBUG

$LOG "Creating temporary directory at $TMP ..." $C_INFO
mkdir -p $TMP

FPS=$(ffprobe -v 0 -of compact=p=0 -select_streams 0 -show_entries stream=r_frame_rate $INVID | sed 's/r_frame_rate=//g')
$LOG "FPS = $FPS" $C_DEBUG
SIZE=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 $INVID)
$LOG "SIZE = $SIZE" $C_DEBUG

$LOG "Exporting orignal video frames into temporary directory ..." $C_INFO
$FFMPEG -i $INVID -r $FPS $TMP$filename%03d.jpg

$LOG "Modifying original video frames  ..." $C_INFO
find $TMP -type f | while read INFRAME; do
    for i in $(seq 1 $PIXELSNUM); do
        mogrify -fill "$(random_hex)" -draw " rectangle $(random_area $SIZE) " $INFRAME
    done
done

$LOG "Exporting orignal audio into temporary directory ..." $C_INFO
$FFMPEG -i $INVID -vn -acodec libmp3lame ${TMP}input-audio.mp3

LENGTH=$(ceil $(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $INVID))
$LOG "LENGTH = $LENGTH" $C_DEBUG

$LOG "Generating noise track of same length as original video ..." $C_INFO
NOISE="noise.mp3"
$FFMPEG -f lavfi -i nullsrc=s=1280x720 -filter_complex "geq=random(1)*255:128:128;aevalsrc=-2+random(0)" -t $LENGTH $TMP$NOISE
$FFMPEG -i $TMP$NOISE -map 0 -map -v ${TMP}void.$NOISE

$LOG "Quieting down noise track ..." $C_INFO
$FFMPEG -i ${TMP}void.$NOISE -filter:a "volume=$NOISEVOL" ${TMP}quiet.$NOISE

$LOG "Merging original audio and noise track into final audio track ..." $C_INFO
$FFMPEG -i ${TMP}input-audio.mp3 -i ${TMP}quiet.$NOISE -filter_complex amix=inputs=2:duration=shortest ${TMP}output-audio.mp3

$LOG "Re-encoding modified frames into video ..." $C_INFO
$FFMPEG -framerate $FPS -pattern_type glob -i "$TMP*.jpg" \
    -c:v libx264 -pix_fmt yuv420p silent.$OUTFILE

$LOG "Re-encoding final audio track into video ..." $C_INFO
$FFMPEG -i silent.$OUTFILE -i ${TMP}output-audio.mp3 -c copy -map 0:v:0 -map 1:a:0 $OUTFILE

$LOG "Cleaning up ..." $C_INFO
rm -rf $TMP silent.$OUTFILE
