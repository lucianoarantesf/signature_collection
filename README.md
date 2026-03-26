# ✍️ SyncSign: Coleta de Assinatura Offline + Envio para API + Persistência em Banco

Este repositório mostra um fluxo completo para captura de assinatura em Delphi FMX, gravação local offline, sincronização via REST e persistência no banco de dados no backend.

## 🏷️ Tecnologias usadas

![Delphi](https://img.shields.io/badge/Delphi-EE1F35?style=for-the-badge)
![Lazarus](https://img.shields.io/badge/Lazarus-2D2D2D?style=for-the-badge)

## Visão geral

O processo foi implementado para funcionar em modelo **offline-first**:

1. Captura a assinatura na tela (toque/mouse) no app FMX.
2. Converte a área desenhada em imagem e salva localmente como `BLOB` (SQLite).
3. Serializa o registro para JSON e converte o `BLOB` para Base64 automaticamente.
4. Envia o payload para a API (Horse/Lazarus) via `POST`.
5. Decodifica Base64 no servidor e grava novamente como `BLOB` no banco definitivo.
6. Marca o registro local como sincronizado (`STATUS_SYNC = 'S'`).

## Estrutura dos exemplos

- `src/uAssinaturaExemplo.pas`: captura da assinatura no front-end e gravação local.
- `src/uSyncExemplo.pas`: rotina de sincronização dos dados pendentes com a API.
- `src/uBackendExemplo.pas`: endpoint de recepção e persistência no backend.

## 1) Coleta da assinatura (FMX)

No arquivo `uAssinaturaExemplo.pas`:

- A assinatura é formada por pontos (`TAssinatura`) coletados nos eventos `MouseMove` e `MouseUp`.
- O desenho é renderizado no `RectangleAssinatura` com `Canvas.DrawLine`.
- Ao salvar, é feito um screenshot da área de desenho com `MakeScreenshot`.
- O bitmap é transformado em `TMemoryStream` e gravado em campo `BLOB` com:

```pascal
LQuery.ParamByName('pBLOB').LoadFromStream(LStream, ftBlob);
```

Também há cuidado com limpeza de memória (`Free`, `Clear`, `Assign(nil)`) para reduzir consumo em Android/iOS.

## 2) Envio para API (sincronização)

No arquivo `uSyncExemplo.pas`:

- Consulta registros pendentes no banco local (`STATUS_SYNC = 'N'`).
- Serializa cada linha para JSON com `DataSet.Serialize` (`ToJSONObject`).
- Campos `BLOB` (assinatura) são convertidos automaticamente para Base64 no payload.
- Envia para API com `RESTRequest4D` (`POST`, timeout, autenticação básica, gzip).
- Se a API retornar sucesso (`STATUS = 'Sucesso'` ou `OK`), atualiza o registro local para sincronizado.

## 3) Recepção na API e gravação no banco

No arquivo `uBackendExemplo.pas`:

- A rota `POST /assinaturas` recebe o JSON.
- A assinatura é lida do campo `assinaturaBase64`.
- O backend decodifica a Base64 para `TMemoryStream` com `TBase64DecodingStream`.
- O stream é persistido no banco com parâmetro `ftBlob` via UniDAC.
- A operação roda em transação (`StartTransaction`, `Commit`, `Rollback`).

## Banco de dados (Oracle, Firebird, SQL Server)

Embora o exemplo esteja orientado para **Oracle**, a arquitetura é **agnóstica de banco** no backend.

Na prática, o fluxo funciona igualmente em **Firebird** e **SQL Server** (ou outro SGBD), desde que:

- exista um campo binário equivalente a `BLOB`/`LOB`;
- a camada de acesso (UniDAC/driver) esteja configurada para esse banco;
- o `LoadFromStream(..., ftBlob)` seja mantido na persistência.

Ou seja: muda o banco/driver e possivelmente o SQL de `INSERT`, mas o conceito de captura, serialização Base64 e gravação binária permanece o mesmo.

## Resumo técnico

- **Frontend:** Delphi FMX
- **Persistência local:** FireDAC + SQLite (`BLOB`, `STATUS_SYNC`)
- **Sincronização:** RESTRequest4D + DataSet.Serialize
- **Backend API:** Horse (Lazarus)
- **Persistência backend:** UniDAC + campo binário (`BLOB`/equivalente)
