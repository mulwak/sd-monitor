# リスティングを読んで、シンボルをアセンブラソースに変換する
# アセンブラの標準機能にあってもよさそうだけど
awk '
BEGIN{
  while(getline~!/Symbols:/){}
  }
$1!~/^__/&&$2~/0x/{
  match($2,/0x[^)]*/)
  print "SDMON_" $1 " = $" substr($2,RSTART+2,RLENGTH-2)}
'
