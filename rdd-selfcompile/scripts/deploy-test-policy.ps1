# 2026-11-11: narrow fixed-artifact test assembly. No live config or launch access.
function Assert-RddOrdinaryPath {
 param([string]$Path)
 $p=[IO.Path]::GetFullPath($Path)
 while($p){
  $item=Get-Item -LiteralPath $p -Force -ErrorAction Stop
  if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'linked path refused'}
  $parent=Split-Path $p -Parent
  if($parent -eq $p){break};$p=$parent
 }
}
function Get-RddTestDeploySource {
 param([string]$MutationId,[string]$ExpectedCommit,[string]$ExpectedSha256,[string]$Mutations,[switch]$Original)
 $fixed=@{
  'mutation-build-ffa63f9a7b714ec6a9168d1b657c8e4d'=@('core:neoforge','numen-neoforge-1.21.1-0.1.3-dev.jar','D8999610E5777B4A8F087C5C59C86C1D54E3187BF0C50EDA520D88DF6E97D056')
  'mutation-build-0057cbc54b26481194dd1bf413c6a8b4'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','E69DBC81A5C4539F83809FBFF89D693295750754ED7278B2B00566B08F007435')
  'mutation-build-52876a2a2dd44cc68009c3ad4992de35'=@('plugins:learner','numen-plugin-learner-1.21.1-0.1.3-dev.jar','BED02091A09889ECBC0DFCF094CAB89B94C9162AB3AD03D93FBE24660660868A')
 }
 $commit='65ffba3ecdd9171eb59af470ba275f9e6655900f'
 # 2026-11-11: bounded no-chain observation fix, only this new RDD artifact.
 if($MutationId -ceq 'mutation-build-6b8413e1eb554f6db920c9760c89a270'){
  $fixed=@{'mutation-build-6b8413e1eb554f6db920c9760c89a270'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','E06DAA86F139312CEB7A7ED4DED5D7312C3DCD2DD6DB6114049AAFF2CD243EFD')}
  $commit='7760964f2f6e0b41d5a56e91d3ba835df9d92530'
 }
 if($MutationId -ceq 'mutation-build-1143a45ccf7c4b2789bb45ddc6dc5590'){
  $fixed=@{'mutation-build-1143a45ccf7c4b2789bb45ddc6dc5590'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','9FCA8846600702A092FC8ED299FAD76CBFC9167039B5A434BDFBDFBCC25CBA9D')}
  $commit='6b87976f9726936497544703fa596088a5ad6f5f'
 }
 if($MutationId -ceq 'mutation-build-a4d56867456a4f18820d070a167ffa0a'){
  $fixed=@{'mutation-build-a4d56867456a4f18820d070a167ffa0a'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','70526EA8562A8B03EB36324D529604D1A8AC2FB1EDA7666106B4301D50FB7D17')}
  $commit='cbe8ad44c0b18f3ab5ec0d2c19ccc7e91e677fe2'
 }
 if($MutationId -ceq 'mutation-build-60befb539f4e4c24b129e05c2f434d6b'){
  $fixed=@{'mutation-build-60befb539f4e4c24b129e05c2f434d6b'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','CF2D115CC63997473668EEF6A13A5F259A4E483FE517BE66F2194B88862509CF')}
  $commit='a5c47538f38ece2b65c0ef863bde865627eb4310'
 }
 if($MutationId -cin @('mutation-build-3fde7607688541eb99b3de87fbbf6ad7','mutation-build-fc5f2711d6a545338719cc95750ce50d')){
  $fixed=@{
   'mutation-build-3fde7607688541eb99b3de87fbbf6ad7'=@('core:neoforge','numen-neoforge-1.21.1-0.1.3-dev.jar','6F543C5CF947F9CE163691663F3124EF3F91C1B6AC79E3A3118D7173BA420E64')
   'mutation-build-fc5f2711d6a545338719cc95750ce50d'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','40D367375CBCEE41723B8162F70F69DB732A4B9CACE2DEE74FAE5AB02A7219E8')
  }
  $commit='e1ad23d0fbb4679e3af749d377b39b6b2da45fbe'
 }
 if($MutationId -ceq 'mutation-build-7a2cded71c3e4230b7cca93ab67aa06f'){
  $fixed=@{'mutation-build-7a2cded71c3e4230b7cca93ab67aa06f'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','04A5195DD1AEE334F20B8B4017E195D8DB360D2614E5E9B8710E2E4AB303562D')}
  $commit='d06618143655f7608890c86ea48a8dcb43dc1341'
 }
 if($MutationId -ceq 'mutation-build-8fe58bf41a5f456fbc5d407e2484fae3'){
  $fixed=@{'mutation-build-8fe58bf41a5f456fbc5d407e2484fae3'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','F90EB4AC7A80EA6D0188432A75A5B9362BFE17E61E45158369588EAC66C54753')}
  $commit='7cf784df48d0362e60fa70e300b7711feaaa9452'
 }
 if($MutationId -ceq 'mutation-build-84a320cad8ea474cab53da9d17480292'){
  $fixed=@{'mutation-build-84a320cad8ea474cab53da9d17480292'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','ACB70945FAE340207EE7D3E08B24547512B522E7ADD475DB0189F05AF94640D9')}
  $commit='7cc063c55b86a1bff83d90237c61a3cd12928abb'
 }
 # 2026-11-12: food cooldown safety fix; same SHA passed kernel and host tests.
 if($MutationId -ceq 'mutation-build-19ecce8338544ef789794af2c268c681'){
  $fixed=@{'mutation-build-19ecce8338544ef789794af2c268c681'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','E13FD247A7627D37135DC060AD31A1D596E53F07AB3D5D150ACB84FBBF4DFE3E')}
  $commit='6d848bdae594859c24e2d3d5e3d0ac48d931f439'
 }
 # 2026-11-12: accepted integration; these three managed artifacts only (204 exact tests).
 if($MutationId -cin @('mutation-build-14e46e1075514aed872cd27fe75b4a4a','mutation-build-34ab8109f7e042559e1de20539924c4d','mutation-build-7130759b9c3044de8a1a8da8c5d1d881')){
  $fixed=@{
   'mutation-build-14e46e1075514aed872cd27fe75b4a4a'=@('core:neoforge','numen-neoforge-1.21.1-0.1.3-dev.jar','5BB40E1D16A1EEB3BAA67CA44997E51474641DE294BF4B2FC0A7E65E1F3BDF36')
   'mutation-build-34ab8109f7e042559e1de20539924c4d'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','8CFDF0C65330BED70D9B32FC044CEB6A70DB893C759CCA96F9EF8CE4B01CE55C')
   'mutation-build-7130759b9c3044de8a1a8da8c5d1d881'=@('plugins:learner','numen-plugin-learner-1.21.1-0.1.3-dev.jar','47EE06D8B870E3C1484E68AD366ECCBABCC5C2E71CA9422B7513FFC9BE53B2C7')
  }
  $commit='bb0f1fd8507d82c4a3d3f9ecc9c6aa5fe5fb94ec'
 }
 # 2026-11-12: 330b verified core and learner only; RDD jar is unchanged.
 if($MutationId -cin @('mutation-build-c9ac2a7723fa4674911de387184698c9','mutation-build-bd0bcda5f6d245ecad714b5f4f022afd')){
  $fixed=@{
   'mutation-build-c9ac2a7723fa4674911de387184698c9'=@('core:neoforge','numen-neoforge-1.21.1-0.1.3-dev.jar','D7170FF629AF27CE7506929CC4CCCC364E38563691D8454C51C767551E34F8E0')
   'mutation-build-bd0bcda5f6d245ecad714b5f4f022afd'=@('plugins:learner','numen-plugin-learner-1.21.1-0.1.3-dev.jar','DE809C7F8EADB2ECF92346471EA71749D42981633B9B6C00FF023A74E9F627CD')
  }
  $commit='330b6f5b2b1fdc814d0e8d5ff2337fe11825ef73'
 }
 # 2026-11-12: e826 exact three verified artifacts for the stopped original live.
 if($MutationId -cin @('mutation-build-1dd867b5ae6a49c7aecc728e958d5dd8','mutation-build-674cea78df824d24b8039ff3f940f0e4','mutation-build-cbb5ea3bc0804bc9ae6a6244c1b68c23')){
  $fixed=@{
   'mutation-build-1dd867b5ae6a49c7aecc728e958d5dd8'=@('core:neoforge','numen-neoforge-1.21.1-0.1.3-dev.jar','6721990F3A46121021BA13AD6721F664662AF4B2432EE36368BA2A4A2FE1A637')
   'mutation-build-674cea78df824d24b8039ff3f940f0e4'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','E7C047BBB321AC431346541291BE8CB493CB26B3329C58011E65BE2210297F9E')
   'mutation-build-cbb5ea3bc0804bc9ae6a6244c1b68c23'=@('plugins:learner','numen-plugin-learner-1.21.1-0.1.3-dev.jar','F5D92CB111AB07B8345E820E79801E9B3ED27E45A27A7F9FD0C9C50CF4DE0FD7')
  }
  $commit='e826813d962090dccaca62e03513079ca3a1fb7a'
 }
 # 2026-11-12: exact owner-findings batch, source/bytes/hash/postcheck verified before release.
 if($MutationId -cin @('mutation-build-1fb466ca58004f7d83afd093013d68c3','mutation-build-937966ec05724882916105cd45f470b4','mutation-build-f0a3c69242714cde8d1152170c1fe931','mutation-build-aea5643ec50a4601a4663e945af7162f')){
  $fixed=@{
   'mutation-build-1fb466ca58004f7d83afd093013d68c3'=@('core:neoforge','numen-neoforge-1.21.1-0.1.3-dev.jar','524966B50E335424F7B9D252C5DEF8F61702C11EABC1E5C80AB79C7C1AFBDC1A')
   'mutation-build-937966ec05724882916105cd45f470b4'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','C4A9403A6A6F45E9D7846F0B88B89BE3D36D8EB706CD11BC35404E192697653F')
   'mutation-build-f0a3c69242714cde8d1152170c1fe931'=@('plugins:learner','numen-plugin-learner-1.21.1-0.1.3-dev.jar','FDDAF2A2431CECB6A059107907F081140D3AF4EC07888BC0E3079261253F8C0F')
   'mutation-build-aea5643ec50a4601a4663e945af7162f'=@('plugins:camera','numen-plugin-camera-1.21.1-0.1.3-dev.jar','1BBCF6E88F2866E1D117C04AC758DFF952A61E6F24E00ACC2F81BC93596F3FD8')
  }
  $commit='4b2f202b3b8df1fa3d54f9961a26c273ef36f9d0'
 }
 # 2026-11-12: frozen main/client consumers passed; four inspected artifacts only.
 if($MutationId -cin @('mutation-build-c0961c5a6e3b46edb927a3236be61058','mutation-build-6ed6b106a2c646018015ee3bc29967cd','mutation-build-dd6531bb6a114bdc85cb01235537e15e','mutation-build-367b48b425d54ae5a48845153342fd4f')){
  $fixed=@{
   'mutation-build-c0961c5a6e3b46edb927a3236be61058'=@('core:neoforge','numen-neoforge-1.21.1-0.1.3-dev.jar','F11A3B6A2459F3D1ED1F792C682C315326E1A8C10AC95DCB5B9DDF331399E1EB')
   'mutation-build-6ed6b106a2c646018015ee3bc29967cd'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','894F7C5E3C08784D75CED0405BC6780976C7A2A8F48C5579C870A51CCD7BB6E5')
   'mutation-build-dd6531bb6a114bdc85cb01235537e15e'=@('plugins:learner','numen-plugin-learner-1.21.1-0.1.3-dev.jar','20F1E8AC2F467880A0728F6161CFE5A250BF21CB4C4381428DE77934A3238D3B')
   'mutation-build-367b48b425d54ae5a48845153342fd4f'=@('plugins:acx','numen-plugin-acx-1.21.1-0.1.3-dev.jar','F91DB3B6342CF90F96C4D62471DB5BA2E4C8FDECB4D52DF9323C0D7976A7AF6C')
  }
  $commit='842d7ee0123a8ead96a04ef673e0c29a2ff4534c'
 }
 # 2026-11-12: 32 exact consumers and MCP namespace re-review passed; this core only.
 if($MutationId -ceq 'mutation-build-4f56fc55b7be483cab7f8e24579d9749'){
  $fixed=@{'mutation-build-4f56fc55b7be483cab7f8e24579d9749'=@('core:neoforge','numen-neoforge-1.21.1-0.1.3-dev.jar','AF772A3F55B206F13E464807F7897FB1F85759A22D92F2D21F0F328336E8CD19')}
  $commit='f7b7c48a1ebbf93dd79e04bc6e596872c187273e'
 }
 # 2026-11-12: 11 exact mine recovery consumers and inspected class bytes; this core only.
 if($MutationId -ceq 'mutation-build-702ea0b018534536977499b23ccee172'){
  $fixed=@{'mutation-build-702ea0b018534536977499b23ccee172'=@('core:neoforge','numen-neoforge-1.21.1-0.1.3-dev.jar','789EF0A21435E7939058E2EDEF74F078386EF2BB7B9E296D54EDF0091FA97E67')}
  $commit='78c3fd296145c79dd3bad5dda643641b2ccf2a70'
 }
 # 2026-11-13: inspected recovery RDD only; never grant isolated-test access to this tuple.
 if($MutationId -ceq 'mutation-build-1fa09220d99b4f78b504e3ea1287cfe5'){
  if(-not $Original){throw 'recovery artifact requires original deployment'}
  $fixed=@{'mutation-build-1fa09220d99b4f78b504e3ea1287cfe5'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','4304CCEADCEA124F60A4034579F7C1BF795B90547AA68A53FEC77A8D323ADD65',1153095)}
  $commit='ba010d4c616caacd78ff871c23965014f11e016c'
 }
 # 2026-11-13: inspected ef5ad core (AttackTool description only); original live only.
 if($MutationId -ceq 'mutation-build-2048390e5f5a4cbb9ed777ed789f28d1'){
  if(-not $Original){throw 'attack core artifact requires original deployment'}
  $fixed=@{'mutation-build-2048390e5f5a4cbb9ed777ed789f28d1'=@('core:neoforge','numen-neoforge-1.21.1-0.1.3-dev.jar','6D116144E3FD9F16D06ADD508CE8080256C62B4D08B8E0B1FD0EC64293318238',3074138)}
  $commit='ef5ad8ec569de625650216c0da78a4c190971496'
 }
 # 2026-11-13: exact e306 durable learner restore consumer, original live only.
 if($MutationId -ceq 'mutation-build-363dd216836540e0b05899ecd4e4002c'){
  if(-not $Original){throw 'learner restore artifact requires original deployment'}
  $fixed=@{'mutation-build-363dd216836540e0b05899ecd4e4002c'=@('plugins:learner','numen-plugin-learner-1.21.1-0.1.3-dev.jar','86D8329A9AB16CF67B04424C79E23B5D4A2529A358B66037FDF9F8AEBF66B1B6',576206)}
  $commit='e3067b3f28536fce3b523c06da2158458d5dd604'
 }
 # 2026-11-13: exact 9314 survival preemption host consumer, original live only.
 if($MutationId -ceq 'mutation-build-a8815be16204427a8297995d57efbcdc'){
  if(-not $Original){throw 'survival replan artifact requires original deployment'}
  $fixed=@{'mutation-build-a8815be16204427a8297995d57efbcdc'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','BF1156C6A7BC09E582B52398CCC414DB30EEC0F3D2A1CDCC123DA95EB8CAF8C9',1159731)}
  $commit='9314ece120631ad6bfe78185b1b73f7c72e4bd43'
 }
 # 2026-11-13: inspected d9 B2 intent artifact; 31 corrected intent tests and unchanged 48 controls, original live only.
 if($MutationId -ceq 'mutation-build-40e931ffc2264468ae8972af764742df'){
  if(-not $Original){throw 'survival intent artifact requires original deployment'}
  $fixed=@{'mutation-build-40e931ffc2264468ae8972af764742df'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','B9D26D7B057C52394531E66B7B3A937C09ECE70D633555DCE95F24845EFDA053',1167110)}
  $commit='d9a76ab43a049809b512d3fff8a52d0180552ee1'
 }
 # 2026-11-13: coherent C1 host and B2 recovery; three audited ec1b physical artifacts only.
 if($MutationId -cin @('mutation-build-f081e4e6f60e4bf090a7d425a81e1158','mutation-build-330e7ece7f8b472bac3b487b8c099e10','mutation-build-1f0beb3c375e44999b96395022952d94')){
  if(-not $Original){throw 'C1 B2 verified artifacts require original deployment'}
  $fixed=@{
   'mutation-build-f081e4e6f60e4bf090a7d425a81e1158'=@('core:neoforge','numen-neoforge-1.21.1-0.1.3-dev.jar','153592F697611659926556DD6F831E06B834C65E0E644FF76D232D58B970A7A9',3079741)
   'mutation-build-330e7ece7f8b472bac3b487b8c099e10'=@('plugins:learner','numen-plugin-learner-1.21.1-0.1.3-dev.jar','C54761114B53AC1B7485D9BB84CE1C20A76D51B1D29EFB93E30A3C09BE5F2D48',610162)
   'mutation-build-1f0beb3c375e44999b96395022952d94'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','391DEADF7430A7BE8781B8919075A118F88B52A7D886A5846F078AA1249C1D26',1171045)
  }
  $commit='ec1b770985b476ae986998957a455a5eeca76fd0'
 }
 # 2026-11-13: only the two inspected 25b6 build receipts; no core/API or RESULT candidate.
 if($MutationId -cin @('mutation-build-1f1a8a7c967947669769dd2c7b6e8eb5','mutation-build-2729529bc6e749dab1bb34cf2ebe96b3')){
  if(-not $Original){throw 'review food artifacts require original deployment'}
  $fixed=@{
   'mutation-build-1f1a8a7c967947669769dd2c7b6e8eb5'=@('plugins:learner','numen-plugin-learner-1.21.1-0.1.3-dev.jar','F8222C4D4DA19EEE07E364241CCF1DECDA982740A1D0E83D00120DC4C4F8D9A2',611020)
   'mutation-build-2729529bc6e749dab1bb34cf2ebe96b3'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','F4A530DB5C33B5C5162AD50159A8F985101BA464D2A7BB2D43B27F16D5F3B605',1171566)
  }
  $commit='25b6f23026e7bd6e6da13465b111d626c3995122'
 }
 # 2026-11-14: source/receipt/hash verified after 131 host+state tests; one learner artifact only.
 if($MutationId -ceq 'mutation-build-0cc0780d079e473d9e35b87ff3ac1a65'){
  if(-not $Original){throw 'result review artifact requires original deployment'}
  $fixed=@{'mutation-build-0cc0780d079e473d9e35b87ff3ac1a65'=@('plugins:learner','numen-plugin-learner-1.21.1-0.1.3-dev.jar','653913D3E0E009045940DC8FF691892F1DC474766A9651DA6FE09FEF4836528C',623053)}
  $commit='1a347ba6b0ab16d2100d926e4ae58316912131ab'
 }
 # 2026-11-14: 39 food controls and 8 A1 controls; two physically audited a199 artifacts only.
 if($MutationId -cin @('mutation-build-ffae833c8c124edd9d9494426c9c577c','mutation-build-a33e86a4a25c4a8782a6ed01c2a44fb3')){
  if(-not $Original){throw 'A1 food artifacts require original deployment'}
  $fixed=@{
   'mutation-build-ffae833c8c124edd9d9494426c9c577c'=@('core:neoforge','numen-neoforge-1.21.1-0.1.3-dev.jar','C88FCC3E215CA7CDEC751D14F0B629CE2C059DF962913B9440E46C063B5160FC',3080159)
   'mutation-build-a33e86a4a25c4a8782a6ed01c2a44fb3'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','1F16C8F52FF6C68F90A22D1630F2AF5411A819DA7E85970C0225892B2D9015FC',1172244)
  }
  $commit='a199d778c3d8be921c5f21f5aae085b80d975106'
 }
  # 2026-11-14: exact compat learner successor; old rollback tuples unchanged.
  if($MutationId -ceq 'mutation-build-412cb9c4933347d99785c5364e5008d9'){
   if(-not $Original){throw 'learner successor artifact requires original deployment'}
   $fixed=@{'mutation-build-412cb9c4933347d99785c5364e5008d9'=@('plugins:learner','numen-plugin-learner-1.21.1-0.1.3-dev.jar','F3FE5621F331B33D982B1CC9B6DF26304049CC04B2AC48AF3178C6BBFDA109CB',624872)}
   $commit='28ba205413b031f91a799fbe35f704831bd8982d'
  }

 # 2026-11-15: exact late-callback learner artifact only; every old rollback tuple stays unchanged.
 if($MutationId -ceq 'mutation-build-d5fcda28252c4f00b4b73edc70fd4a05'){
  if(-not $Original){throw 'own-learner late artifact requires original deployment'}
  $fixed=@{'mutation-build-d5fcda28252c4f00b4b73edc70fd4a05'=@('plugins:learner','numen-plugin-learner-1.21.1-0.1.3-dev.jar','886ECA7AF36A0D8273E8FB0591CF6D9322C05B9017B68EB7D98AA4CE34F23BF8',637775)}
  $commit='1e40290cfad3e64a9fd4f3e1a015c73dd92e3646'
 }

 # 2026-11-14: inspected 86785 nudge RDD; original live only, no new source-root channel.
 if($MutationId -ceq 'mutation-build-9ac2a358204d457eb7a02ace7eabd9cb'){
  if(-not $Original){throw 'nudge RDD artifact requires original deployment'}
  $fixed=@{'mutation-build-9ac2a358204d457eb7a02ace7eabd9cb'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','A2F081963BDB715D73D26D433A1C0977941DE30515EFA017AB8EB228DD392106',1173314)}
  $commit='86785a7a61cc0cbeff5e0d32262d6e7dd829c194'
 }

 # 2026-11-14: exact same-source aa735 plugin artifacts only; old rollback tuples remain unchanged.
 if($MutationId -cin @('mutation-build-2f09f207d2d146619c65dc236c0b08c1','mutation-build-9d7b663c3b04480ca78d80461399b4b2','mutation-build-d4121062b6e54cd78ffb32a6a86e23e5')){
  if(-not $Original){throw 'parallel aa735 artifacts require original deployment'}
  $fixed=@{
   'mutation-build-2f09f207d2d146619c65dc236c0b08c1'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','2FB0E0636B106DB48140DF5EFF859CDDAAC3350A15815933DD8DA9E54ACE588F',1173437)
   'mutation-build-9d7b663c3b04480ca78d80461399b4b2'=@('plugins:learner','numen-plugin-learner-1.21.1-0.1.3-dev.jar','3570AF13D57BA5F4ABF77D6064C4B9EEC82A81605EF29849B4F1FF00795094E6',625493)
   'mutation-build-d4121062b6e54cd78ffb32a6a86e23e5'=@('plugins:experience','numen-plugin-experience-1.21.1-0.1.3-dev.jar','99E188C606F72C40675926FDC432B1BEB5EA647E1E1F160C3A6DA23600BF3CBC',206899)
  }
  $commit='aa73586a069361aea5d263618d0dfa8b1bc40df3'
 }

 # 2026-11-14: exact same-source 8853 plugin artifacts only; old rollback tuples remain unchanged.
 if($MutationId -cin @('mutation-build-bcf9062caa914d12b1d75a250e8bd5ee','mutation-build-5a5fccbb162244d0906d26be8d7f329d','mutation-build-7cc1a6f15b61475587953bf380d8f7b1')){
  if(-not $Original){throw 'parallel 8853 artifacts require original deployment'}
  $fixed=@{
   'mutation-build-bcf9062caa914d12b1d75a250e8bd5ee'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','8136345A8FFBC1322BC289B7CBEFF37479E9FC9D2573963CC6DB09B3674A9DCE',1188631)
   'mutation-build-5a5fccbb162244d0906d26be8d7f329d'=@('plugins:learner','numen-plugin-learner-1.21.1-0.1.3-dev.jar','F42716BC0C6C3CD980C3080614F356B58F7C6D9C47860360E1081CA33A07459F',637503)
   'mutation-build-7cc1a6f15b61475587953bf380d8f7b1'=@('plugins:experience','numen-plugin-experience-1.21.1-0.1.3-dev.jar','6371B7BF3926EBE8AA27A8A2AD63196A8B8F41C72E36ADB9EBA620755E717C00',207504)
  }
  $commit='8853c569e6e51d0bc23a39b4b5dcdea7f685f69a'
 }

 # 2026-11-14: V25 inspected two-plugin successor; retain every earlier rollback tuple.
 if($MutationId -cin @('mutation-build-4ee45e827c1e439eb95638a175a68177','mutation-build-f59304e827ee473bb10022854c2aaf2f')){
  if(-not $Original){throw 'V25 artifacts require original deployment'}
  $fixed=@{
   'mutation-build-4ee45e827c1e439eb95638a175a68177'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','8B85F50E48BFCB922D15D0E46CD9F7E7EF75C125F826C396D3CE9E8DDBEE6B28',1191094)
   'mutation-build-f59304e827ee473bb10022854c2aaf2f'=@('plugins:experience','numen-plugin-experience-1.21.1-0.1.3-dev.jar','BD66DFDB53A0702B6884093A36AB0D0D10A005EFF6741C7A7915ED3EB949D7A5',207622)
  }
  $commit='144ac9570932de65b80ae61d0ffffcb317934922'
 }

 # 2026-11-15: V26 five-class source integration; two audited 5c046 artifacts only, older tuples unchanged.
 if($MutationId -cin @('mutation-build-fcfb896670ac47fc8c07725fae837c77','mutation-build-f5e19b3475a44df281915f229f2c1366')){
  if(-not $Original){throw 'V26 artifacts require original deployment'}
  $fixed=@{
   'mutation-build-fcfb896670ac47fc8c07725fae837c77'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','BECF06531DB5E3911D91834B2785E3DB73AF4308331D6B3F0D9FB19BE306D01B',1192911)
   'mutation-build-f5e19b3475a44df281915f229f2c1366'=@('core:neoforge','numen-neoforge-1.21.1-0.1.3-dev.jar','2FC60365B898D3ACC903F461A2791864F48188670F21B02E05DD5E2AEFCE2989',3080162)
  }
  $commit='5c046644683b26b385ef06e57260f3aa16edfb1b'
 }

 # 2026-11-15: exact V27 convo restore core artifact only; every old rollback tuple stays unchanged.
 if($MutationId -ceq 'mutation-build-c7b23cc99dfc4b8ea2f8a7da92606a2b'){
  if(-not $Original){throw 'V27 convo restore core artifact requires original deployment'}
  $fixed=@{'mutation-build-c7b23cc99dfc4b8ea2f8a7da92606a2b'=@('core:neoforge','numen-neoforge-1.21.1-0.1.3-dev.jar','9959267A3CC8D8B982ACEF99EAEB95030B75D5C6E83D4E3F85B5E74C236DCAC1',3081940)}
  $commit='1f2e86286113430b58425446a132b986d482cf10'
 }

 # 2026-11-15: exact V28 KB-quota core artifact only; every old rollback tuple stays unchanged.
 if($MutationId -ceq 'mutation-build-e5184f70bd7b41fdabdc3f85cbf17306'){
  if(-not $Original){throw 'V28 KB-quota core artifact requires original deployment'}
  $fixed=@{'mutation-build-e5184f70bd7b41fdabdc3f85cbf17306'=@('core:neoforge','numen-neoforge-1.21.1-0.1.3-dev.jar','FB48F4779F68827A3CCD8EDBAE002A6D2F769EBED005C6298E16C1556CC00A4D',3083591)}
  $commit='83ddd36f00aecd64b220155bf53658dbac776df0'
 }

 # 2026-11-15: exact V30 daily-condition RDD artifact only; every old rollback tuple stays unchanged.
 if($MutationId -ceq 'mutation-build-faa7ff97c0c44bb6b9d36aef17281ae9'){
  if(-not $Original){throw 'V30 daily-condition RDD artifact requires original deployment'}
  $fixed=@{'mutation-build-faa7ff97c0c44bb6b9d36aef17281ae9'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','C9798F2F4068266AF4574400ABD754B6CEF814D08B23E5A4FA3DC569E9A4C1E1',1195737)}
  $commit='faede91ce4bf0ff5c9253df798988a4f4f8fddf9'
 }

 # 2026-11-15: exact B2/C1 9f94 RDD artifact only; every old rollback tuple stays unchanged.
 if($MutationId -ceq 'mutation-build-c3a130228cf54d41a05fa168e0446338'){
  if(-not $Original){throw 'B2/C1 9f94 RDD artifact requires original deployment'}
  $fixed=@{'mutation-build-c3a130228cf54d41a05fa168e0446338'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','18C226A3450D36DE2CD4B126F4D639FA4A66E154AC9979DC02E91EEFD28F00DA',1193497)}
  $commit='9f94bbbad357687538dc4c50498ae05a729d7f86'
 }

 # 2026-11-16: exact manual integration core (embedded API) and RDD only; old tuples unchanged.
 if($MutationId -cin @('mutation-build-917da3d407814f27bb8479f2d1c0b452','mutation-build-d2949d98ceab4084a3f18dedde8da948')){
  if(-not $Original){throw 'manual 0fada artifacts require original deployment'}
  $fixed=@{
   'mutation-build-917da3d407814f27bb8479f2d1c0b452'=@('core:neoforge','numen-neoforge-1.21.1-0.1.3-dev.jar','3CA192EEF304964FC3C4424C5992A83F0E8E369A9741FABE177F15A3235D61B1',2568296)
   'mutation-build-d2949d98ceab4084a3f18dedde8da948'=@('plugins:rdd','numen-plugin-rdd-1.21.1-0.1.3-dev.jar','3814920BB30BA6B47E3A97FBF2C92FEF540D19AB9EC416A110F849AE1BC8D3BC',1206594)
  }
  $commit='0fada9b87cf75f719a7c0de9d269ff7009281b17'
 }

 if($ExpectedCommit -cne $commit -or -not $fixed.ContainsKey($MutationId)){throw 'unapproved source selection'}
 $f=$fixed[$MutationId];if($ExpectedSha256 -ine $f[2]){throw 'expected sha differs from fixed artifact'}
 $dir=Join-Path $Mutations $MutationId
 $phase=Join-Path $dir 'phase-build.json';Assert-RddOrdinaryPath $phase
 $r=Get-Content -LiteralPath $phase -Raw -Encoding UTF8 | ConvertFrom-Json
 $artifact=[IO.Path]::GetFullPath((Join-Path (Join-Path $dir 'jar') $f[1]))
 if([IO.Path]::GetFullPath($r.artifact) -ine $artifact){throw 'artifact escapes fixed mutation jar'}
 Assert-RddOrdinaryPath $artifact
 if($r.status -cne 'passed' -or $r.success -ne $true -or $null -eq $r.gradleExit -or $r.gradleExit -ne 0 -or $r.deployed -ne $false -or $r.stage -cne 'build-only' -or $r.module -cne $f[0] -or $r.instance -cne 'test' -or $r.mutationId -cne $MutationId){throw 'invalid build receipt'}
 if($r.sourceHead -cne $commit -or $r.sourceHeadAfter -cne $commit -or $r.expectedCommit -cne $commit -or $null -eq $r.sourceDirtyCount -or $null -eq $r.sourceDirtyCountAfter -or $r.sourceDirtyCount -ne 0 -or $r.sourceDirtyCountAfter -ne 0 -or $r.sourceProof -cne 'pre-post-checks-consistent'){throw 'invalid source proof'}
 $sha=(Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash
 if($sha -ine $f[2] -or $r.sha256 -ine $sha -or (Get-Item -LiteralPath $artifact).Length -ne $r.bytes){throw 'artifact hash or size mismatch'}
 if($f.Count -gt 3 -and $r.bytes -ne $f[3]){throw 'artifact hash or size mismatch'}
 return @{dir=$dir;artifact=$artifact;name=$f[1];sha=$sha;commit=$commit;module=$f[0]}
}
function Get-RddTestDeployState {
 param([string]$Root)
 try{
  $procs=@(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" -ErrorAction Stop)
  if($procs.Count -eq 0){return 'STOPPED'} # successful CIM enumeration, no Java process
  $matches=@($procs | ForEach-Object {Get-RddMcCommandLineMatch -CommandLine $_.CommandLine -GameDir $Root})
  return Get-RddMcStateFromMatches $matches
 }catch{return 'UNKNOWN'}
}
function Invoke-RddTestAssembly {
 param($Source,[string]$Root,[string]$Live,[switch]$Original)
 Assert-RddOrdinaryPath $Root;Assert-RddOrdinaryPath $Live
 if($Original){
  # 2026-11-12: original live learner exception is this exact managed source tuple only.
  $fixedLearner=$Source.module -ceq 'plugins:learner' -and $Source.name -ceq 'numen-plugin-learner-1.21.1-0.1.3-dev.jar' -and $Source.commit -ceq '65ffba3ecdd9171eb59af470ba275f9e6655900f' -and $Source.sha -ieq 'BED02091A09889ECBC0DFCF094CAB89B94C9162AB3AD03D93FBE24660660868A'
  $fixedIntegration=$Source.commit -ceq 'bb0f1fd8507d82c4a3d3f9ecc9c6aa5fe5fb94ec' -and (
   ($Source.module -ceq 'core:neoforge' -and $Source.name -ceq 'numen-neoforge-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq '5BB40E1D16A1EEB3BAA67CA44997E51474641DE294BF4B2FC0A7E65E1F3BDF36') -or
   ($Source.module -ceq 'plugins:rdd' -and $Source.name -ceq 'numen-plugin-rdd-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq '8CFDF0C65330BED70D9B32FC044CEB6A70DB893C759CCA96F9EF8CE4B01CE55C') -or
   ($Source.module -ceq 'plugins:learner' -and $Source.name -ceq 'numen-plugin-learner-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq '47EE06D8B870E3C1484E68AD366ECCBABCC5C2E71CA9422B7513FFC9BE53B2C7'))
  $fixedNext=$Source.commit -ceq '330b6f5b2b1fdc814d0e8d5ff2337fe11825ef73' -and (
   ($Source.module -ceq 'core:neoforge' -and $Source.name -ceq 'numen-neoforge-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq 'D7170FF629AF27CE7506929CC4CCCC364E38563691D8454C51C767551E34F8E0') -or
   ($Source.module -ceq 'plugins:learner' -and $Source.name -ceq 'numen-plugin-learner-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq 'DE809C7F8EADB2ECF92346471EA71749D42981633B9B6C00FF023A74E9F627CD'))
  $fixedE826=$Source.commit -ceq 'e826813d962090dccaca62e03513079ca3a1fb7a' -and (
   ($Source.module -ceq 'core:neoforge' -and $Source.name -ceq 'numen-neoforge-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq '6721990F3A46121021BA13AD6721F664662AF4B2432EE36368BA2A4A2FE1A637') -or
   ($Source.module -ceq 'plugins:rdd' -and $Source.name -ceq 'numen-plugin-rdd-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq 'E7C047BBB321AC431346541291BE8CB493CB26B3329C58011E65BE2210297F9E') -or
   ($Source.module -ceq 'plugins:learner' -and $Source.name -ceq 'numen-plugin-learner-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq 'F5D92CB111AB07B8345E820E79801E9B3ED27E45A27A7F9FD0C9C50CF4DE0FD7'))
  $fixedOwnerFindings=$Source.commit -ceq '4b2f202b3b8df1fa3d54f9961a26c273ef36f9d0' -and (
   ($Source.module -ceq 'core:neoforge' -and $Source.name -ceq 'numen-neoforge-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq '524966B50E335424F7B9D252C5DEF8F61702C11EABC1E5C80AB79C7C1AFBDC1A') -or
   ($Source.module -ceq 'plugins:rdd' -and $Source.name -ceq 'numen-plugin-rdd-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq 'C4A9403A6A6F45E9D7846F0B88B89BE3D36D8EB706CD11BC35404E192697653F') -or
   ($Source.module -ceq 'plugins:learner' -and $Source.name -ceq 'numen-plugin-learner-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq 'FDDAF2A2431CECB6A059107907F081140D3AF4EC07888BC0E3079261253F8C0F') -or
   ($Source.module -ceq 'plugins:camera' -and $Source.name -ceq 'numen-plugin-camera-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq '1BBCF6E88F2866E1D117C04AC758DFF952A61E6F24E00ACC2F81BC93596F3FD8'))
  $fixedRuntimeFollowups=$Source.commit -ceq '842d7ee0123a8ead96a04ef673e0c29a2ff4534c' -and (
   ($Source.module -ceq 'core:neoforge' -and $Source.name -ceq 'numen-neoforge-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq 'F11A3B6A2459F3D1ED1F792C682C315326E1A8C10AC95DCB5B9DDF331399E1EB') -or
   ($Source.module -ceq 'plugins:rdd' -and $Source.name -ceq 'numen-plugin-rdd-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq '894F7C5E3C08784D75CED0405BC6780976C7A2A8F48C5579C870A51CCD7BB6E5') -or
   ($Source.module -ceq 'plugins:learner' -and $Source.name -ceq 'numen-plugin-learner-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq '20F1E8AC2F467880A0728F6161CFE5A250BF21CB4C4381428DE77934A3238D3B') -or
   ($Source.module -ceq 'plugins:acx' -and $Source.name -ceq 'numen-plugin-acx-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq 'F91DB3B6342CF90F96C4D62471DB5BA2E4C8FDECB4D52DF9323C0D7976A7AF6C'))
  $fixedTransportExternal=$Source.commit -ceq 'f7b7c48a1ebbf93dd79e04bc6e596872c187273e' -and $Source.module -ceq 'core:neoforge' -and $Source.name -ceq 'numen-neoforge-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq 'AF772A3F55B206F13E464807F7897FB1F85759A22D92F2D21F0F328336E8CD19'
  $fixedMineRecovery=$Source.commit -ceq '78c3fd296145c79dd3bad5dda643641b2ccf2a70' -and $Source.module -ceq 'core:neoforge' -and $Source.name -ceq 'numen-neoforge-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq '789EF0A21435E7939058E2EDEF74F078386EF2BB7B9E296D54EDF0091FA97E67'
  $fixedRecoveryRdd=$Source.commit -ceq 'ba010d4c616caacd78ff871c23965014f11e016c' -and $Source.module -ceq 'plugins:rdd' -and $Source.name -ceq 'numen-plugin-rdd-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq '4304CCEADCEA124F60A4034579F7C1BF795B90547AA68A53FEC77A8D323ADD65'
  $fixedAttackContractCore=$Source.commit -ceq 'ef5ad8ec569de625650216c0da78a4c190971496' -and $Source.module -ceq 'core:neoforge' -and $Source.name -ceq 'numen-neoforge-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq '6D116144E3FD9F16D06ADD508CE8080256C62B4D08B8E0B1FD0EC64293318238'
  $fixedLearnerRestore=$Source.commit -ceq 'e3067b3f28536fce3b523c06da2158458d5dd604' -and $Source.module -ceq 'plugins:learner' -and $Source.name -ceq 'numen-plugin-learner-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq '86D8329A9AB16CF67B04424C79E23B5D4A2529A358B66037FDF9F8AEBF66B1B6'
  $fixedSurvivalReplan=$Source.commit -ceq '9314ece120631ad6bfe78185b1b73f7c72e4bd43' -and $Source.module -ceq 'plugins:rdd' -and $Source.name -ceq 'numen-plugin-rdd-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq 'BF1156C6A7BC09E582B52398CCC414DB30EEC0F3D2A1CDCC123DA95EB8CAF8C9'
  $fixedSurvivalIntent=$Source.commit -ceq 'd9a76ab43a049809b512d3fff8a52d0180552ee1' -and $Source.module -ceq 'plugins:rdd' -and $Source.name -ceq 'numen-plugin-rdd-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq 'B9D26D7B057C52394531E66B7B3A937C09ECE70D633555DCE95F24845EFDA053'
  # 2026-11-13: preserve old plugin interfaces; accept only these exact reviewed ec1b tuples.
  $fixedEc1b=$Source.commit -ceq 'ec1b770985b476ae986998957a455a5eeca76fd0' -and (
   ($Source.module -ceq 'core:neoforge' -and $Source.name -ceq 'numen-neoforge-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq '153592F697611659926556DD6F831E06B834C65E0E644FF76D232D58B970A7A9') -or
   ($Source.module -ceq 'plugins:learner' -and $Source.name -ceq 'numen-plugin-learner-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq 'C54761114B53AC1B7485D9BB84CE1C20A76D51B1D29EFB93E30A3C09BE5F2D48') -or
   ($Source.module -ceq 'plugins:rdd' -and $Source.name -ceq 'numen-plugin-rdd-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq '391DEADF7430A7BE8781B8919075A118F88B52A7D886A5846F078AA1249C1D26'))
  # Exact new tuples only; all old tuple checks below remain unchanged.
  $fixedReviewFood=$Source.commit -ceq '25b6f23026e7bd6e6da13465b111d626c3995122' -and (
   ($Source.module -ceq 'plugins:learner' -and $Source.name -ceq 'numen-plugin-learner-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq 'F8222C4D4DA19EEE07E364241CCF1DECDA982740A1D0E83D00120DC4C4F8D9A2') -or
   ($Source.module -ceq 'plugins:rdd' -and $Source.name -ceq 'numen-plugin-rdd-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq 'F4A530DB5C33B5C5162AD50159A8F985101BA464D2A7BB2D43B27F16D5F3B605'))
  # 2026-11-14: exact learner only; API/core remain installed and the existing 25b6 rollback remains valid.
  $fixedResultReview=$Source.commit -ceq '1a347ba6b0ab16d2100d926e4ae58316912131ab' -and $Source.module -ceq 'plugins:learner' -and $Source.name -ceq 'numen-plugin-learner-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq '653913D3E0E009045940DC8FF691892F1DC474766A9651DA6FE09FEF4836528C'
  # 2026-11-14: exact A1/food core and RDD only; learner and old rollback selections stay unchanged.
  $fixedSuccessor=$Source.commit -ceq '28ba205413b031f91a799fbe35f704831bd8982d' -and $Source.module -ceq 'plugins:learner' -and $Source.name -ceq 'numen-plugin-learner-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq 'F3FE5621F331B33D982B1CC9B6DF26304049CC04B2AC48AF3178C6BBFDA109CB'
  # 2026-11-14: one nudge RDD tuple only; core/API/learner and old rollback remain untouched.
  $fixedNudgeRdd=$Source.commit -ceq '86785a7a61cc0cbeff5e0d32262d6e7dd829c194' -and $Source.module -ceq 'plugins:rdd' -and $Source.name -ceq 'numen-plugin-rdd-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq 'A2F081963BDB715D73D26D433A1C0977941DE30515EFA017AB8EB228DD392106'
  # 2026-11-14: the same three aa735 module/name/hash tuples; never a commit-wide release lane.
  $fixedParallel=$Source.commit -ceq 'aa73586a069361aea5d263618d0dfa8b1bc40df3' -and (
   ($Source.module -ceq 'plugins:rdd' -and $Source.name -ceq 'numen-plugin-rdd-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq '2FB0E0636B106DB48140DF5EFF859CDDAAC3350A15815933DD8DA9E54ACE588F') -or
   ($Source.module -ceq 'plugins:learner' -and $Source.name -ceq 'numen-plugin-learner-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq '3570AF13D57BA5F4ABF77D6064C4B9EEC82A81605EF29849B4F1FF00795094E6') -or
   ($Source.module -ceq 'plugins:experience' -and $Source.name -ceq 'numen-plugin-experience-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq '99E188C606F72C40675926FDC432B1BEB5EA647E1E1F160C3A6DA23600BF3CBC'))
  # 2026-11-14: the same three 8853 module/name/hash tuples; never a commit-wide release lane.
  $fixedWhy8853=$Source.commit -ceq '8853c569e6e51d0bc23a39b4b5dcdea7f685f69a' -and (
   ($Source.module -ceq 'plugins:rdd' -and $Source.name -ceq 'numen-plugin-rdd-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq '8136345A8FFBC1322BC289B7CBEFF37479E9FC9D2573963CC6DB09B3674A9DCE') -or
   ($Source.module -ceq 'plugins:learner' -and $Source.name -ceq 'numen-plugin-learner-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq 'F42716BC0C6C3CD980C3080614F356B58F7C6D9C47860360E1081CA33A07459F') -or
   ($Source.module -ceq 'plugins:experience' -and $Source.name -ceq 'numen-plugin-experience-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq '6371B7BF3926EBE8AA27A8A2AD63196A8B8F41C72E36ADB9EBA620755E717C00'))
  # The same two V25 module/name/hash tuples; no source-commit-wide assembly permission.
  $fixedV25=$Source.commit -ceq '144ac9570932de65b80ae61d0ffffcb317934922' -and (
   ($Source.module -ceq 'plugins:rdd' -and $Source.name -ceq 'numen-plugin-rdd-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq '8B85F50E48BFCB922D15D0E46CD9F7E7EF75C125F826C396D3CE9E8DDBEE6B28') -or
   ($Source.module -ceq 'plugins:experience' -and $Source.name -ceq 'numen-plugin-experience-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq 'BD66DFDB53A0702B6884093A36AB0D0D10A005EFF6741C7A7915ED3EB949D7A5'))
  $fixedA1Food=$Source.commit -ceq 'a199d778c3d8be921c5f21f5aae085b80d975106' -and (
   ($Source.module -ceq 'core:neoforge' -and $Source.name -ceq 'numen-neoforge-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq 'C88FCC3E215CA7CDEC751D14F0B629CE2C059DF962913B9440E46C063B5160FC') -or
   ($Source.module -ceq 'plugins:rdd' -and $Source.name -ceq 'numen-plugin-rdd-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq '1F16C8F52FF6C68F90A22D1630F2AF5411A819DA7E85970C0225892B2D9015FC'))
   # The same two V26 module/name/hash tuples; no source-commit-wide assembly permission.
  $fixedV26=$Source.commit -ceq '5c046644683b26b385ef06e57260f3aa16edfb1b' -and (
   ($Source.module -ceq 'plugins:rdd' -and $Source.name -ceq 'numen-plugin-rdd-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq 'BECF06531DB5E3911D91834B2785E3DB73AF4308331D6B3F0D9FB19BE306D01B') -or
   ($Source.module -ceq 'core:neoforge' -and $Source.name -ceq 'numen-neoforge-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq '2FC60365B898D3ACC903F461A2791864F48188670F21B02E05DD5E2AEFCE2989'))
  $fixedB2C1=$Source.commit -ceq '9f94bbbad357687538dc4c50498ae05a729d7f86' -and $Source.module -ceq 'plugins:rdd' -and $Source.name -ceq 'numen-plugin-rdd-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq '18C226A3450D36DE2CD4B126F4D639FA4A66E154AC9979DC02E91EEFD28F00DA'
  $fixedConvo=$Source.commit -ceq '1f2e86286113430b58425446a132b986d482cf10' -and $Source.module -ceq 'core:neoforge' -and $Source.name -ceq 'numen-neoforge-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq '9959267A3CC8D8B982ACEF99EAEB95030B75D5C6E83D4E3F85B5E74C236DCAC1'
  $fixedKbQuota=$Source.commit -ceq '83ddd36f00aecd64b220155bf53658dbac776df0' -and $Source.module -ceq 'core:neoforge' -and $Source.name -ceq 'numen-neoforge-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq 'FB48F4779F68827A3CCD8EDBAE002A6D2F769EBED005C6298E16C1556CC00A4D'
  $fixedOwnLearnerLate=$Source.commit -ceq '1e40290cfad3e64a9fd4f3e1a015c73dd92e3646' -and $Source.module -ceq 'plugins:learner' -and $Source.name -ceq 'numen-plugin-learner-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq '886ECA7AF36A0D8273E8FB0591CF6D9322C05B9017B68EB7D98AA4CE34F23BF8'
  $fixedDailyFaede=$Source.commit -ceq 'faede91ce4bf0ff5c9253df798988a4f4f8fddf9' -and $Source.module -ceq 'plugins:rdd' -and $Source.name -ceq 'numen-plugin-rdd-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq 'C9798F2F4068266AF4574400ABD754B6CEF814D08B23E5A4FA3DC569E9A4C1E1'
  $fixedManual=$Source.commit -ceq '0fada9b87cf75f719a7c0de9d269ff7009281b17' -and (
   ($Source.module -ceq 'core:neoforge' -and $Source.name -ceq 'numen-neoforge-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq '3CA192EEF304964FC3C4424C5992A83F0E8E369A9741FABE177F15A3235D61B1') -or
   ($Source.module -ceq 'plugins:rdd' -and $Source.name -ceq 'numen-plugin-rdd-1.21.1-0.1.3-dev.jar' -and $Source.sha -ieq '3814920BB30BA6B47E3A97FBF2C92FEF540D19AB9EC416A110F849AE1BC8D3BC'))
  if($Root -cne 'D:/rdd/mc/The Best of Twilight Forest' -or (-not $fixedManual -and -not $fixedV25 -and -not $fixedV26 -and -not $fixedB2C1 -and -not $fixedConvo -and -not $fixedKbQuota -and -not $fixedOwnLearnerLate -and -not $fixedDailyFaede -and -not $fixedWhy8853 -and -not $fixedParallel -and -not $fixedNudgeRdd -and -not $fixedA1Food -and -not $fixedSuccessor -and -not $fixedResultReview -and -not $fixedReviewFood -and -not $fixedEc1b -and -not $fixedSurvivalIntent -and -not $fixedSurvivalReplan -and -not $fixedLearnerRestore -and -not $fixedAttackContractCore -and -not $fixedRecoveryRdd -and -not $fixedMineRecovery -and -not $fixedTransportExternal -and -not $fixedRuntimeFollowups -and -not $fixedOwnerFindings -and -not $fixedLearner -and -not $fixedIntegration -and -not $fixedNext -and -not $fixedE826 -and $Source.commit -cnotin @('6b87976f9726936497544703fa596088a5ad6f5f','cbe8ad44c0b18f3ab5ec0d2c19ccc7e91e677fe2','a5c47538f38ece2b65c0ef863bde865627eb4310','e1ad23d0fbb4679e3af749d377b39b6b2da45fbe','d06618143655f7608890c86ea48a8dcb43dc1341','7cf784df48d0362e60fa70e300b7711feaaa9452','7cc063c55b86a1bff83d90237c61a3cd12928abb','6d848bdae594859c24e2d3d5e3d0ac48d931f439'))){throw 'unapproved original deployment'}
 }elseif([IO.Path]::GetFullPath($Root) -ieq [IO.Path]::GetFullPath($Live)){throw 'test root is live'}
 $mods=Join-Path $Root 'mods';Assert-RddOrdinaryPath $mods
 if((Get-RddTestDeployState $Root) -cne 'STOPPED'){throw 'test instance not proven stopped'}
 $dest=Join-Path $mods $Source.name
 if(Test-Path -LiteralPath $dest){Assert-RddOrdinaryPath $dest}
 $api=Join-Path $mods 'numen_api-neoforge-1.21.1-0.1.3-dev.jar'
 if($Source.module -ceq 'core:neoforge' -and (Test-Path -LiteralPath $api)){Assert-RddOrdinaryPath $api}
 $attempt='deploy-test-'+[guid]::NewGuid().ToString('N')
 $receipt=Join-Path $Source.dir ($attempt+'.json')
 $backupRoot=Join-Path $Root 'disabled'
 if(Test-Path $backupRoot){Assert-RddOrdinaryPath $backupRoot}else{New-Item -ItemType Directory $backupRoot | Out-Null}
 $backup=Join-Path $backupRoot $attempt;New-Item -ItemType Directory $backup | Out-Null
 $r=@{stage='deploy-test';status='pending';success=$false;instance='test';root=$Root;sourceCommit=$Source.commit;module=$Source.module;sha256=$Source.sha;artifact=$Source.artifact;backups=@();receipt=$receipt}
 try{
  foreach($old in @($dest,$api)){
   if($old -eq $api -and $Source.module -cne 'core:neoforge'){continue}
   if(-not (Test-Path -LiteralPath $old)){continue}
   $oldHash=(Get-FileHash -LiteralPath $old -Algorithm SHA256).Hash
   $saved=Join-Path $backup ([IO.Path]::GetFileName($old))
   [IO.File]::Copy($old,$saved,$false)
   if((Get-FileHash $saved -Algorithm SHA256).Hash -cne $oldHash){throw 'backup hash mismatch'}
   $r.backups+=@{original=$old;saved=$saved;sha256=$oldHash}
  }
  if($Source.module -ceq 'core:neoforge' -and (Test-Path -LiteralPath $api)){[IO.File]::Delete($api)}
  [IO.File]::Copy($Source.artifact,$dest,$true)
  if((Get-FileHash $dest -Algorithm SHA256).Hash -cne $Source.sha){throw 'destination hash mismatch'}
  $r.status='DEPLOYED_TEST';$r.success=$true
 }catch{$r.status='failed';$r.reason=$_.Exception.Message;throw}finally{
  [IO.File]::WriteAllText($receipt,($r|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
 }
 return $r
}
