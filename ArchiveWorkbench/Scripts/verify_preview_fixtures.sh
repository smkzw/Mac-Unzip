#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}/TestFixtures/PreviewDocuments"
output="$(mktemp -d /tmp/archive-workbench-quicklook.XXXXXX)"
trap 'rm -rf "$output"' EXIT

/usr/bin/qlmanage -t -x -s 256 -o "$output" \
  "$root/示例.png" \
  "$root/示例.mp4" \
  "$root/示例.pdf" \
  "$root/示例.docx" \
  "$root/示例.xlsx" \
  "$root/示例.pptx"

for name in 示例.png 示例.mp4 示例.pdf 示例.docx 示例.xlsx 示例.pptx; do
  test -s "$output/$name.png"
done

echo "Quick Look verified image, video, PDF, Word, Excel, and PowerPoint fixtures."
