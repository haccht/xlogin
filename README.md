# xlogin
rancid clogin alternatives

ネットワークデバイスへのログインを自動化するツール群。  
`xlogin/firmares`にファームウェア仕様を記述することで対象機器を拡大可能。


各個別装置毎のログインのための認証情報は`~/.xloginrc`へ記述しておく。  
`.xloginrc`のフォーマットは下記。項目はタブ区切り。

~~~
#hostname	hosttype	telnet_uri_scheme	options
vyos01	vyos	telnet://vagrant:vagrant@127.0.0.1:2200
vyos02	vyos	telnet://vagrant:vagrant@127.0.0.1:2201
~~~
