# Computer on Linux and VNC desktops

`--host vnc://host[:port]` drives any X desktop over RFB. It is coordinate-only: no `describe`, no `--id`, no `get-text`, and `--raise` has no effect. Read the screen from screenshots.

- A screenshot's pixels are click coordinates when its `scale` is 1; otherwise divide by `scale`. The `saved:` line prints it (`(1024x768, …, origin [0,0], scale 1)`), as does `--json`.
- Every input verb (`click`, `right-click`, `type-text`, `key`, `scroll`, `drag`) returns once the screen has stopped changing. Do not `sleep` between actions or before a screenshot. An app that is still opening shows on the next screenshot; take one instead of sleeping.
- Add `--screenshot <path>` to an action to get the screen after it in the same call, then read that file. A separate `screenshot` call is only needed before your first action.
- Chain the steps of one form into one call: `computer click --x 640 --y 300 && computer type-text --text "Jane" && computer click --x 640 --y 380 && computer type-text --text "jane@example.com" --screenshot ./form.png`.
- Native dropdowns and menus open on a click; take a screenshot of the open list before clicking an option.
- Type a date into a date field with its separators (`type-text --text "03/15/2024"`); its segments do not advance on digits alone. If a calendar popup opened, press `key --keys Escape` first; typed text does not reach the field while it is open.
- Drag sliders and items with `computer drag --from x,y --to x,y`.
- Send several keys in one call: `computer key --keys "Right,1,5,Tab"`.
- Scroll by pixels at a point inside the scrolling area: `computer scroll --x 640 --y 450 --dy -300` scrolls down about 300 px.
