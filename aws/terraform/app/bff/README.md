# bff構築手順

## 事前準備

* Terraformのバージョンはこれを利用
  
```sh
terraform -version
~
Terraform v1.2.6
on linux_amd64
```

* ECRにリポジトリを作成  
  <https://zenn.dev/nicopin/books/58c922f51ea349/viewer/9c8f46>

* ECRにイメージをpush  
  対象アプリのGitリポジトリのREADME.mdを参照

## Terraformで構築

* 環境毎のディレクトリに移動

* ワークスペースの初期化(初回だけ)  
  Terraform を実行するためには、1番初めに terraform init でワークスペースを初期化することが必須となっています。terraform init を実行すると、.tf ファイルで利用している plugin（aws provider など）のダウンロード処理などが走ります。
  
```sh
terraform init
~
Terraform has been successfully initialized!
~
```

* 実行計画を参照  
  .tf ファイルに記載された情報を元に、どのようなリソースが 作成/修正/削除 されるかを参照することが可能になります。今回のケースだとリソースの作成となるので “+create” と出力されました。
  
```sh
terraform plan
```

* リソースの作成  
  .tf ファイルに記載された情報を元にリソースを作成するコマンド。
リソースが作成されると terraform.state というファイルに、作成されたリソースに関連する情報が保存されます。また、2度目以降の実行後には、1世代前のものが terraform.tfstate.backup に保存される形となります。Terraform において、この状態を管理する terraform.state ファイルが非常に重要になってくるようです。

```sh
terraform apply
~
※実行を確定するためにyesと入力してもらうと実際に構築が始まります。

Plan: 45 to add, 0 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: 
~
```

* リソースの確認  
  AWSコンソールを確認して想定通り作成されているかを確認する

* ヘルスチェックのパスにアクセスして起動を確認する  
  <https://api.unchi.ga/actuator/health>

* リソースの状態を参照  

```sh
terraform show
```

* リソースを削除  
  .tf ファイルに記載された情報を元にリソースを削除するコマンド。
なお、実行すると terraform.tfstate のリソース情報がスカスカになり、削除直前のものは terraform.tfstate.backup に保存される形となります。

```sh
terraform destroy
~
※実行を確定するためにyesと入力してもらうと実際に構築が始まります。

Plan: 0 to add, 0 to change, 45 to destroy.

Do you really want to destroy all resources?
  Terraform will destroy all your managed infrastructure, as shown above.
  There is no undo. Only 'yes' will be accepted to confirm.

  Enter a value: 
~
```
