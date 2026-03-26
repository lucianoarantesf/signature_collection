unit uBackendExemplo;

{$mode Delphi}

interface

uses
  Classes, SysUtils, Horse, LazUTF8, fpjson, jsonparser, DB, base64, Uni;

type
  { TServiceMock: Simula um DataModule contendo a conexão UniDAC }
  TServiceMock = class
  private
    FConn: TUniConnection;
    FQueryInsert: TUniQuery;
  public
    constructor Create;
    destructor Destroy; override;
    
    // Transforma a string Base64 do JSON de volta para Stream Binário
    procedure DecodeBase64ToStream(AStream: TStream; const S: string; Strict: boolean = false);
    
    property Conn: TUniConnection read FConn;
    property QueryInsert: TUniQuery read FQueryInsert;
  end;

type
  { TPostSignatureController: Classe que registra as rotas no Horse }
  TPostSignatureController = class
    class procedure Registry;
  end;

implementation

{ ==============================================================================
  1. SERVIÇO: DECODIFICAÇÃO E BANCO DE DADOS (UNIDAC)
  ============================================================================== }
constructor TServiceMock.Create;
begin
  FConn := TUniConnection.Create(nil);
  FQueryInsert := TUniQuery.Create(nil);
  FQueryInsert.Connection := FConn;
  
  // Exemplo de SQL. Na prática, configure pelo Object Inspector.
  FQueryInsert.SQL.Text := 'INSERT INTO TABELA_IMAGENS (ASSINATURA_BLOB) VALUES (:pBLOB)';
end;

destructor TServiceMock.Destroy;
begin
  FQueryInsert.Free;
  FConn.Free;
  inherited;
end;

procedure TServiceMock.DecodeBase64ToStream(AStream: TStream; const S: string; Strict: boolean = false);
var
  SD: String;
  InStream: TStringStream;
  Decoder: TBase64DecodingStream;
begin
  if Length(S) = 0 then Exit;
  
  SD := S;
  // Ajuste do padding obrigatório do Base64
  while Length(SD) mod 4 > 0 do SD := SD + '=';
  
  InStream := TStringStream.Create(SD);
  try
    if Strict then
      Decoder := TBase64DecodingStream.Create(InStream, bdmStrict)
    else
      Decoder := TBase64DecodingStream.Create(InStream, bdmMIME);
    try
      // Copia a cadeia decodificada para o MemoryStream destino
      AStream.CopyFrom(Decoder, Decoder.Size);
      AStream.Position := 0; // Rewind obrigatório antes de salvar no DB
    finally
      Decoder.Free;
    end;
  finally
    InStream.Free;
  end;
end;

{ ==============================================================================
  2. CONTROLLER: RECEPÇÃO HTTP VIA HORSE
  ============================================================================== }
procedure OnPostSignature(Req: THorseRequest; Res: THorseResponse);
var
  LService: TServiceMock;
  LJsonRes: TJSONObject;
  LJsonBody: TJSONObject;
  LJsonData: TJSONData;
  LStreamBlob: TMemoryStream;
begin
  LService := TServiceMock.Create;
  LJsonRes := TJSONObject.Create;

  try
    // 1. Recebe o Body (JSON) da requisição POST
    LJsonData := GetJSON(Req.Body);
    LJsonBody := LJsonData as TJSONObject;

    // Inicia controle transacional com banco de dados
    LService.Conn.StartTransaction;
    try
      LService.QueryInsert.Close;

      // ... Injeção de parâmetros textuais omitida por segurança ...

      // 2. Extração e Decodificação da Imagem
      LStreamBlob := TMemoryStream.Create;
      try
        // Lê a String Base64 direto do nó do JSON e converte para Stream na memória
        LService.DecodeBase64ToStream(LStreamBlob, LJsonBody.Get('assinaturaBase64'));

        // 3. Persistência Nativa (ftBlob) para o Oracle
        LService.QueryInsert.ParamByName('pBLOB').LoadFromStream(LStreamBlob, ftBlob);
        
        LService.QueryInsert.Execute;
      finally
        // Liberação de RAM essencial (O motor do DB já fez a cópia para a rede)
        LStreamBlob.Free;
      end;

      // 4. Constrói Resposta HTTP de Sucesso
      LJsonRes.Clear;
      LJsonRes.Add('CODIGO', 200);
      LJsonRes.Add('STATUS', 'Sucesso');

      Res.ContentType('application/json').Status(200).Send(LJsonRes.AsJSON);

      LService.Conn.Commit;
    except
      on E: Exception do
      begin
        LService.Conn.Rollback;
        
        // Constrói Resposta HTTP de Erro
        LJsonRes.Clear;
        LJsonRes.Add('CODIGO', 500);
        LJsonRes.Add('STATUS', UTF8Decode('Falha ao inserir: ' + Copy(E.Message, 0, 81)));
        
        Res.ContentType('application/json').Status(500).Send(LJsonRes.AsJSON);
        Exit;
      end;
    end;

  finally
    // Controle seguro contra Memory Leaks na API (Servidor não pode reiniciar)
    if Assigned(LJsonRes) then FreeAndNil(LJsonRes);
    if Assigned(LJsonData) then FreeAndNil(LJsonData); 
    if Assigned(LService) then FreeAndNil(LService);
  end;
end;

class procedure TPostSignatureController.Registry;
begin
  // Registra o Endpoint no Horse Framework
  THorse.Post('assinaturas', OnPostSignature);
end;

end.