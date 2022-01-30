#!/bin/bash

# Required tools:
#   awk, bash, bc, sed, sort, ...
#   ghostscript
#   imagemagick
#   img2pdf
#   mupdf-tools
#   pdfjam (texlive-extra-utils)
#   pdftk
#   poppler-utils
#   pspdftool

# We take the name of a single input file on the command line.
[ "$#" -eq 1 ] || exit 1
inp="$1"

# Output file goes into the "imposed" directory.
mkdir -p imposed
[[ "${inp}" =~ / ]] && dir="${inp%%/*}/" || dir=
out="${dir}imposed/${inp##*/}"
cover=''

# Pages for the body and the cover of the book.
# Pages are selected using the same syntax that "pdftk" understands.
# Additionally, there are the following special page selectors:
#   B         - insert a blank page
#   [uU](url) - download a JPEG file and insert it as a single (u) page or
#               a two-page spread (U)
#   D page#   - turn the selected page and include it as a two-page spread
#               (should be followed by "left" or "right")
select="1-end"
front=
back=

# Number of signatures to generate
signatures=10

# Font and positioning information to use for page numbers.
# Use "strings ${inp}|grep FontName" to find a good candidate for the font.
# Leave "font" blank to omit page numbers.
font=
nopagenumbers=""
fontsize=8
numoddpos=474pt
numevenpos=23pt
numypos=30pt

# Size of each page in the book in inches
paperwidth=5.5
paperheight=8.5

# Trim on left, bottom, right, and top, if necessary
trim='.7in 2in 1.15in 1in'

# Size of printable are (only used when including external images)
contentwidth=
contentheight=

# Size of two-page spreads in inches
spreadwidth=
spreadheight=

# Normalize inputfile page size.
tmp="${out%.pdf}~.pdf"
tmp2="${tmp%.pdf}~.pdf"
pdfjam -q --papersize "{${paperwidth}in,${paperheight}in}" "${inp}" \
       ${trim:+--trim "${trim}" --clip true} --outfile "${tmp}"

# Insert two-page spread(s).
spreadfiles=
for i in ${select}; do
  j="$(printf '%s' "${spreadfiles}" | wc -w)"
  img="${tmp%.pdf}img.jpg"
  spreaddoc="${img%.jpg}~${j}.pdf"
  tag="$(echo "${j}" | tr 0-9 A-J)"
  isspread=1-2
  if [[ "${i}" =~ ^([uU])'('([^\)]+)')'$ ]]; then
    curl -s "${BASH_REMATCH[2]}" -o "${img}"
    if [ "${BASH_REMATCH[1]}" = "U" ]; then
      img2pdf -o "${tmp2}" \
              -S "$(scale=4;bc <<<"2*${paperwidth}")inx${paperheight}in" \
              -b "$(bc <<<"scale=4;(${paperheight}-${spreadheight})/2")in:$(bc \
                       <<<"scale=4;${paperwidth}-${spreadwidth}/2")in" \
              "${img}"
      mutool poster -x 2 "${tmp2}" "${spreaddoc}"
    else
      img2pdf -o "${spreaddoc}" -S "${paperwidth}inx${paperheight}in" \
              -b "$(bc <<<"scale=4;(${paperheight}-${contentheight})/2")in:$(bc\
                       <<<"scale=4;(${paperwidthwidth}-${contentwidth})/2")in" \
              "${img}"
      isspread=
    fi
    rm -f "${img}"
  elif [[ "${i}" =~ ^D(([0-9]+)(left|right))$ ]]; then
    rm -f "${spreaddoc}"
    j="$(pdfimages -f "${BASH_REMATCH[2]}" -l "${BASH_REMATCH[2]}" \
                   -list "${tmp}" |
         awk '/jpeg/{ print $15 " " $2 }' |  numfmt --from=iec --suffix=B |
         sort -nr | awk 'NR==1 { print $2 }')"
    if [ -n "${j}" ]; then
      dir="${tmp%.pdf}dir"
      mkdir -p "${dir}"
      pdfimages -f "${BASH_REMATCH[2]}" -l "${BASH_REMATCH[2]}" -all "${tmp}" \
                "${dir}/x"
      convert "${dir}/$(printf 'x-%03d.jpg' "${j}")" -rotate \
              $([ "${BASH_REMATCH[3]}" = left ] && echo ' -90' ||
                [ "${BASH_REMATCH[3]}" = right ] && echo 90 || :) \
              -fuzz 10% -trim -trim -quality 100 \
              +repage -format pdf "${spreaddoc}" >&/dev/null || :
      rm -rf "${dir}"
    fi
    if ! [ -s "${spreaddoc}" ]; then
      # If we couldn't find an image file that was suitable for extraction,
      # we'll have to do things the hard way. We somewhat arbitarily set the
      # scan resolution to 600dpi. This can severely bloat output files, and
      # in some cases it can still result in poor output quality. So, the
      # "pdfimages" solution, if available, is much more preferable.
      pdftk "${tmp}" cat "${BASH_REMATCH[1]}" output "${tmp2}"
      convert -density 600 "${tmp2}" -fuzz 10% -trim -trim +repage \
              -format pdf "${spreaddoc}"
    fi
    pdfjam -q --papersize "{$(bc <<<"${paperwidth}*2")in,${paperheight}in}" \
           "${spreaddoc}" --outfile "${tmp2}"
    mutool poster -x 2 "${tmp2}" "${spreaddoc}"
  else
    continue
  fi
  # Add the spread file to the selection of pages. There might or might
  # not be a trailing blank page. So, explicitly select the first two
  # pages, only.
  spreadfiles="${spreadfiles} XS${tag}=${spreaddoc}"
  select="${select%%${i}*} S${tag}${isspread} ${select#*${i}}"
done
select="$(printf '%s' "${select}" | sed 's/\s\+/ /g;s/^\s//;s/\s$//')"

# And add some extra margin. This needs to be adjusted, if the papersize
# changes.
### pdftk "${tmp}" output "${tmp2}" uncompress
### # Before adjustment, a half-letter looks like this: /MediaBox [0 0 396 612]
### sed -i 's,^/MediaBox\s*\[[^]]*\],/MediaBox [ -30 -20 456 652 ],' "${tmp2}"
### pdfjam -q --papersize "{${paperwidth}in,${paperheight}in}" "${tmp2}" \
###        --outfile "${tmp}"

# Generate cover, if requested.
blank="${tmp%.pdf}blank.pdf"
echo | ps2pdf -dDEVICEWIDTHPOINTS=$(bc <<<"${paperwidth}*72") \
              -dDEVICEHEIGHTPOINTS=$(bc <<<"${paperheight}*72") \
              - "${blank}"
[ -n "${cover}" ] && {
  pdftk X="${tmp}" B="${blank}" cat B X"${front}" B B B B X"${back}" \
        output "${tmp2}"
  pdfjam -q --papersize "{${paperwidth}in,${paperheight}in}" --landscape \
         --twoside --nup 2x1 "${tmp2}" --outfile "${cover}"
}

# Select desired pages from input file and pad with blank pages to
# a multiple of four pages.
pdftk X="${tmp}" XB="${blank}" $spreadfiles cat X${select// / X} XB XB XB \
      output "${tmp2}"
pages="$(pdfinfo "${tmp2}" | awk '/Pages:/{ print $2 }')"
pages=$((4*(pages/4)))
rm -f "${blank}" ${left} ${right} $(echo "${spreadfiles}"|sed 's/XS[A-J]\+=//g')

# Separate into odd/even pages and insert page numbers at the bottom
# right/left of each page. Then merge back into a single file.
if [ -n "${font}" ]; then
  odd="${tmp%.pdf}odd.pdf"; odd2="${tmp%.pdf}odd2.pdf"
  even="${tmp%.pdf}even.pdf"; even2="${tmp%.pdf}even2.pdf"
  pspdftool "number(x=${numoddpos}, y=${numypos}, start=1, size=${fontsize},
                    font=\"${font}\")" "${tmp2}" "${odd}"
  pspdftool "number(x=${numevenpos}, y=${numypos}, start=1, size=${fontsize},
             font=\"${font}\")" "${tmp2}" "${even}"
  pdftk "${odd}" cat odd output "${odd2}"
  pdftk "${even}" cat even output "${even2}"
  pdftk "${odd2}" "${even2}" shuffle output "${tmp}"
  tmp3="${tmp2%.pdf}~.pdf"
  pdftk N="${tmp}" U="${tmp2}" cat $(
    i=1
    for j in ${nopagenumbers}; do
      [ ${i} -ge ${j} ] || echo "N${i}-$((j-1))"
      echo "U${j}"
      i=$((j+1))
    done
    [ ${i} -gt ${pages} ] || echo "N${i}-${pages}") \
        output "${tmp3}"
  mv "${tmp3}" "${tmp}"
  rm -f "${odd}" "${even}" "${odd2}" "${even2}" "${tmp2}"
else
  mv "${tmp2}" "${tmp}"
fi

# Compute imposition sequence for the desired number of signatures.
: && {
  nxt=1
  impose=$(
    for i in $(seq "${signatures}"); do
      start="${nxt}"
      end=$(((pages*i+3)/4/signatures*4))
      nxt=$((end+1))
      while [ "${start}" -lt "${end}" ]; do
        printf '%s%d %d %d %d' "$([ "${start}" -ne 1 ] && printf ' ')" \
               ${end} ${start} $((start+1)) $((end-1))
        start=$((start+2))
        end=$((end-2))
      done
    done)
} || impose="1 $(seq "${pages}"|tr '\n' ' '|sed 's/ $//')"

# Impose pages into the final output file.
pdfjam -q --papersize "{${paperheight}in,$(bc <<<"${paperwidth}*2")in}" \
       --landscape --twoside --nup 2x1 "${tmp}" "${impose// /,}" \
       --outfile "${out}"

# Clean up.
rm -f "${tmp}"
