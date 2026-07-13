# QuickCopy

QuickCopyは、macOSのメニューバーに常駐するコピー補助アプリです。

基本操作:

1. 他のアプリでテキストをドラッグ選択する
2. マウスを離す
3. 2秒以内に右ダブルクリックする
4. QuickCopyがCommand + Cを送信する

## ビルド

```sh
make bundle
```

アプリは次の場所に生成されます。

```text
.build/QuickCopy.app
```

ビルド時にシンプルなアプリ登録用アイコンも生成され、`.app`に組み込まれます。

## 起動

```sh
make run
```

`make run` はアプリを `/Applications/QuickCopy.app` にコピーしてから起動します。
アクセシビリティ設定に登録するときは、この `/Applications/QuickCopy.app` を選んでください。

初回起動時は、次の場所でQuickCopyを許可してください。

```text
システム設定 > プライバシーとセキュリティ > アクセシビリティ
```

設定画面に出てこない場合は、`+` ボタンから `/Applications/QuickCopy.app` を直接選択してください。
古い `.build/QuickCopy.app` や `~/Applications/QuickCopy.app` を許可していた場合は、いったん削除して `/Applications/QuickCopy.app` を追加し直すのがおすすめです。

## メニュー

- `QuickCopy: オン/オフ`: 機能の有効・無効を切り替える
- `モード`: 右ダブルクリック / Option + 右ダブルクリックを切り替える
- `権限`: アクセシビリティ権限を確認する
- `システム設定を開く`: アクセシビリティ設定を開く
- `QuickCopyを終了`: アプリを終了する

右クリックはmacOS標準のコンテキストメニューも開くため、対象アプリによってはメニューが表示されます。コピー自体は右ダブルクリック検知時にCommand + Cを送信します。
