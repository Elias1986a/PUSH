-- notes-spelling.applescript get|off|on : Notes' "Check Spelling While Typing" and "Check Grammar With Spelling".
on run argv
	set what to item 1 of argv
	tell application "System Events" to tell process "Notes"
		set m to menu 1 of menu item "Spelling and Grammar" of menu "Edit" of menu bar 1
		set out to ""
		repeat with nm in {"Check Spelling While Typing", "Check Grammar With Spelling"}
			set it_ to menu item nm of m
			set isOn to (value of attribute "AXMenuItemMarkChar" of it_) is not missing value
			set out to out & nm & "=" & isOn & "; "
			if (what is "off" and isOn) or (what is "on" and not isOn) then click it_
		end repeat
	end tell
	return out
end run
