#! /usr/bin/python3
import sys
import re

if len(sys.argv) != 3:
    sys.exit('Usage: ' + sys.argv[0] + ' <regex> <string>')
regex = sys.argv[1]
string_to_match = sys.argv[2]
if not re.match(regex, string_to_match):
    sys.exit('ERROR: The string "' + string_to_match + '" is NOT matching the pattern "' + regex + '"')
print('OK: The string "' + string_to_match + '" is matching the pattern "' + regex + '"')
