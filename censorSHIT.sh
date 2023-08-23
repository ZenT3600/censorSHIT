#!/usr/bin/bash

set -e

function log_echo() {
    echo "[$2] $1"
}

function log_gum() {
    echo '{{Color "'$2'" " (*)"}}{{ Color "'$C_MUTE'" " ['$(date)']" }}' $1 | gum format -t template
}

LOG="log_gum"

function require_gum() {
    if ! type "gum" > /dev/null; then echo "!!! Missing recommended dependency: gum !!!" && LOG="log_echo"; fi
}

function require() {
    if ! type "$1" > /dev/null; then echo "!!! Missing required dependency: $1 !!!" && exit -2; fi
}

require_gum
require bc
require openssl
require ffmpeg
require mogrify

C_ERR=1
C_INFO=10
C_WARN=11
C_MUTE=8
C_DEBUG=4

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
    W=$(( $(echo $1 | sed 's/x.*//g') - 1))
    H=$(( $(echo $1 | sed 's/.*x//g') - 1 ))
    X=$(echo $(($RANDOM % $W)))
    Y=$(echo $(($RANDOM % $H)))
    echo -n "$X,$Y $(( $X + 1 )),$(( $Y + 1 ))"
}


INVID="$1"
if [ -z $INVID ]; then
    $LOG "Invalid input file" $C_ERR
    exit -1
fi
TMP="tmp/"

$LOG "Creating temporary directory at $TMP ..." $C_INFO
mkdir -p $TMP
FPS=$(ffprobe -v 0 -of compact=p=0 -select_streams 0 -show_entries stream=r_frame_rate $INVID | sed 's/r_frame_rate=//g')
$LOG "Found FPS to be $FPS!" $C_DEBUG
SIZE=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 $INVID)
$LOG "Found SIZE to be $SIZE!" $C_DEBUG
$LOG "Exporting orignal video frames into temporary directory ..." $C_INFO
$FFMPEG -i $INVID -r $FPS $TMP$filename%03d.jpg
$LOG "Modifying original video frames  ..." $C_INFO
find $TMP -type f | while read INFRAME; do
    mogrify -fill "$(random_hex)" -draw " rectangle $(random_area $SIZE) " $INFRAME
done
$LOG "Exporting orignal audio into temporary directory ..." $C_INFO
$FFMPEG -i $INVID -vn -acodec libmp3lame ${TMP}input-audio.mp3
NOISE="noise.mp3"
LENGTH=$(ceil $(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $INVID) )
$LOG "Found LENGTH to be $LENGTH!" $C_DEBUG
$LOG "Generating noise track of same length as original video ..." $C_INFO
$FFMPEG -f lavfi -i nullsrc=s=1280x720 -filter_complex "geq=random(1)*255:128:128;aevalsrc=-2+random(0)" -t $LENGTH $TMP$NOISE
$FFMPEG -i $TMP$NOISE -map 0 -map -v ${TMP}void.$NOISE
$LOG "Quieting down noise track ..." $C_INFO
$FFMPEG -i ${TMP}void.$NOISE -filter:a "volume=0.2" ${TMP}quiet.$NOISE
$LOG "Merging original audio and noise track into final audio track ..." $C_INFO
$FFMPEG -i ${TMP}input-audio.mp3 -i ${TMP}quiet.$NOISE -filter_complex amix=inputs=2:duration=shortest ${TMP}output-audio.mp3
$LOG "Re-encoding modified frames into video ..." $C_INFO
$FFMPEG -framerate $FPS -pattern_type glob -i 'tmp/*.jpg' \
  -c:v libx264 -pix_fmt yuv420p silent.out.mp4
$LOG "Re-encoding final audio track into video ..." $C_INFO
$FFMPEG -i silent.out.mp4 -i ${TMP}output-audio.mp3 -c copy -map 0:v:0 -map 1:a:0 out.mp4
$LOG "Cleaning up ..." $C_INFO
rm -rf $TMP silent.out.mp4