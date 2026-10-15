tell application "System Events" to tell process "Notes"
	repeat with x in (every window)
		try
			click (first button of x whose subrole is "AXCloseButton")
		end try
	end repeat
end tell
tell application "Notes"
	activate
	set n to make new note at folder "Notes" of default account with properties {body:"<div><br></div>"}
	show n
end tell
delay 1.5
tell application "System Events" to tell process "Notes"
	click menu item "Hide Others" of menu 1 of menu bar item "Notes" of menu bar 1
	click menu item "Open Note in New Window" of menu "Window" of menu bar 1
	delay 1.5
	set w to front window
	set position of w to {902, 914}
	set size of w to {500, 330}
	click menu item "Body" of menu "Format" of menu bar 1
	repeat 1 times
		click menu item "Zoom In" of menu "View" of menu bar 1
		delay 0.2
	end repeat
	repeat with x in (every window whose name is not "New Note")
		try
			click (first button of x whose subrole is "AXCloseButton")
		end try
	end repeat
	perform action "AXRaise" of (first window whose name is "New Note")
end tell
