package web

import (
	"fmt"
	"strings"

	qrcode "github.com/skip2/go-qrcode"
)

// QRSVG renders an inline SVG QR code matching app.py's qr_svg(): error
// correction M, 1-module quiet zone, currentColor stroke, no background rect,
// no fixed width/height (scales to CSS container).
func QRSVG(url string, scale int) (string, error) {
	if scale <= 0 {
		scale = 4
	}
	q, err := qrcode.New(url, qrcode.Medium)
	if err != nil {
		return "", err
	}
	q.DisableBorder = true
	bitmap := q.Bitmap()
	const border = 1
	n := len(bitmap)
	dim := (n + 2*border) * scale

	var d strings.Builder
	for y, row := range bitmap {
		x := 0
		for x < len(row) {
			if !row[x] {
				x++
				continue
			}
			start := x
			for x < len(row) && row[x] {
				x++
			}
			fmt.Fprintf(&d, "M%d %d.5h%d", start+border, y+border, x-start)
		}
	}
	return fmt.Sprintf(
		`<svg viewBox="0 0 %d %d" class="segno"><path transform="scale(%d)" class="qrline" stroke="currentColor" d="%s"/></svg>`,
		dim, dim, scale, d.String(),
	), nil
}
