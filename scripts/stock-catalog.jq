# Product derivatives may inherit the channel model, polarity and target paper.
def info($all; $id):
  $all[$id] as $p |
  if $p == null then error("Missing stock profile: " + $id)
  elif $p.derived_from then info($all; $p.derived_from) + $p.info
  else $p.info end;

reduce inputs as $p ({}; .[(input_filename | split("/") | last | rtrimstr(".json"))] = $p)
| . as $all | [keys[] as $id | info($all; $id) as $s |
  if ($s.type != "positive" and $s.type != "negative") then error("Unknown polarity: " + $id) else
  {id: $id, name: $s.name, paper: ($s.support == "paper" or $s.stage == "printing"),
   reversal: ($s.type == "positive"), monochrome: ($s.channel_model == "bw"),
   targetPrint: ($s.target_print // ""),
   group: (if $s.channel_model == "bw" then "黑白" elif $s.type == "positive" then "反转片" else "彩色负片" end)} end]
