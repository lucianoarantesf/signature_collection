# ✍️ SyncSign: Arquitetura Offline-First de Captura e Sincronização de Assinaturas (FMX para REST API)

Este projeto demonstra a implementação completa de um fluxo de captura de assinaturas digitais em um aplicativo Mobile (Delphi FMX), armazenamento local seguro (SQLite), e sincronização com um Backend REST (Horse / Lazarus) que armazena os dados em formato binário.

## 🚀 O Desafio
Criar um ecossistema leve e responsivo para tablets/smartphones que funcione 100% offline, capture assinaturas desenhadas pelo usuário na tela, e sincronize esses dados de forma assíncrona, convertendo imagens brutas em formatos seguros para tráfego via rede (Base64) e armazenamento otimizado no banco (BLOB).

## 🛠️ Stack Tecnológico
* **Frontend Mobile:** Delphi (FireMonkey / FMX)
* **Banco de Dados Local:** SQLite (FireDAC)
* **Serialização & REST:** RESTRequest4D, DataSet.Serialize
* **Backend API:** Lazarus + Horse Framework
* **Acesso a Dados API:** UniDAC
* **Banco de Dados Oficial:** Oracle Database

## ⚙️ Arquitetura e Fluxo de Dados

### 1. Captura Visual e Gerenciamento de Memória (FMX)
A assinatura é coletada capturando os eventos de toque (`MouseMove`, `MouseUp`) dentro de um componente `TRectangle`, gerando um traço vetorial.
Para salvar, o aplicativo extrai um print do componente usando o método nativo `MakeScreenshot`. 

### 2. Armazenamento Local (SQLite Offline-First)
As imagens geradas são convertidas em `TMemoryStream` e salvas localmente em campos do tipo `BLOB` utilizando o FireDAC.
```pascal
// Exemplo de injeção de stream de forma segura sem perder a referência da memória
LQuery.ParamByName('ASSINATURA').LoadFromStream(LStream, ftBlob);
```

### 3. Serialização e Sincronismo (REST)
No momento em que o dispositivo detecta conexão com a internet, a rotina de sincronismo é acionada.
Utilizando a biblioteca DataSet.Serialize, a query do banco local é convertida diretamente para JSON. O grande diferencial desta biblioteca é a conversão automática e nativa dos campos BLOB locais para Strings Base64 dentro do payload JSON.

### 4. Recepção e Decodificação no Backend (Horse + Lazarus)
A API construída em Horse recebe o POST contendo o payload em JSON.
Ao invés de alocar DataSets pesados na memória do servidor, a API faz a leitura direta dos nós do JSON (ex: lJsonBody.Get('assinatura')), decodificando a string Base64 novamente para um TMemoryStream.

``` pascal
// Exemplo do Decoder no Backend
Decoder := TBase64DecodingStream.Create(InStream, bdmMIME);
AStream.CopyFrom(Decoder, Decoder.Size);
```

### 5. Persistência Definitiva (Oracle DB)
Com o Stream reconstruído na memória do servidor, a API utiliza o UniDAC para executar um INSERT no banco de dados Oracle, mapeando o parâmetro como ftBlob. Isso garante que o dado seja salvo nos LOB Segments do Oracle, mantendo o consumo de disco extremamente baixo (média de 45 KB alocados por registro no servidor).
