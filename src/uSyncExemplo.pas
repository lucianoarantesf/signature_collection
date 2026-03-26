unit uSyncExemplo;

interface

uses
  System.Classes, System.SysUtils, System.JSON,
  REST.Json, Data.DB, DateUtils,
  // Bibliotecas de REST e Serialização modernas
  RESTRequest4D, DataSet.Serialize, DataSet.Serialize.Config,
  // FireDAC para Banco de Dados Local (SQLite)
  FireDAC.Comp.Client, FireDAC.Comp.DataSet, FireDAC.Stan.Intf,
  FireDAC.Stan.Option, FireDAC.Stan.Param;

type
  { TSyncExemplo: 
    Classe responsável por orquestrar a sincronização entre o banco de dados 
    local (Offline-First) e a API REST (Nuvem). }
  TSyncExemplo = class
  private
    FConexaoLocal: TFDConnection;
    FQueryConsulta: TFDQuery;
    FQueryAtualiza: TFDQuery;
    FUrlAPI: String;

    // Função genérica e encapsulada para fazer o POST HTTP via RESTRequest4D
    function EnviarPostAPI(const AResource, AJsonPayload: String): String;
  public
    constructor Create(AConexao: TFDConnection; const ABaseURL: String);
    destructor Destroy; override;

    // Rotina principal que varre o banco e envia os dados
    procedure ExportarDadosPendentes(vReenvia: Boolean = False);
  end;

implementation

{ TSyncExemplo }

constructor TSyncExemplo.Create(AConexao: TFDConnection; const ABaseURL: String);
begin
  FConexaoLocal := AConexao;
  FUrlAPI := ABaseURL;

  // Inicializa as Queries locais
  FQueryConsulta := TFDQuery.Create(nil);
  FQueryConsulta.Connection := FConexaoLocal;

  FQueryAtualiza := TFDQuery.Create(nil);
  FQueryAtualiza.Connection := FConexaoLocal;
  FQueryAtualiza.SQL.Text := 'UPDATE TABELA_DADOS SET STATUS_SYNC = :pSTATUS WHERE ID = :pID';

  // Configuração global da serialização (Ignora case sensitivity de chaves JSON)
  TDataSetSerializeConfig.GetInstance.CaseNameDefinition := cndNone;
end;

destructor TSyncExemplo.Destroy;
begin
  FQueryConsulta.Free;
  FQueryAtualiza.Free;
  inherited;
end;

{ ==============================================================================
  1. MOTOR DE REQUISIÇÃO REST (RESTRequest4D)
  ============================================================================== }
function TSyncExemplo.EnviarPostAPI(const AResource, AJsonPayload: String): String;
var
  LResponse: IResponse;
begin
  try
    // Constrói a requisição com Timeout de segurança, Auth e compressão (GZIP)
    LResponse := TRequest.New
      .BaseURL(FUrlAPI)
      .Resource(AResource)
      .BasicAuthentication('UsuarioAPI', 'SenhaAPI_123')
      .ContentType('application/json')
      .AcceptEncoding('gzip')
      .Timeout(120000)
      .AddBody(AJsonPayload)
      .Post;

    // Retorna o conteúdo recebido do servidor (Ex: {"STATUS": "Sucesso", "CODIGO": 200})
    Result := LResponse.Content;

  except
    on E: Exception do
      raise Exception.Create('Falha de conexão com a API: ' + E.Message);
  end;
end;

{ ==============================================================================
  2. ORQUESTRADOR DE SINCRONISMO E SERIALIZAÇÃO
  ============================================================================== }
procedure TSyncExemplo.ExportarDadosPendentes(vReenvia: Boolean);
var
  LJsonPayload: TJSONObject;
  LMemTableResposta: TFDMemTable;
begin
  LMemTableResposta := TFDMemTable.Create(nil);
  try
    // 1. Filtra no SQLite apenas os registros criados offline (STATUS = 'N')
    FQueryConsulta.SQL.Clear;
    FQueryConsulta.SQL.Add('SELECT * FROM TABELA_DADOS WHERE 1=1');
    
    if vReenvia then
      FQueryConsulta.SQL.Add('AND STATUS_SYNC <> ''N''')
    else
      FQueryConsulta.SQL.Add('AND STATUS_SYNC = ''N''');

    FQueryConsulta.Open;

    if FQueryConsulta.IsEmpty then Exit;

    FQueryConsulta.First;
    while not FQueryConsulta.Eof do
    begin
      // 2. A MÁGICA DA SERIALIZAÇÃO:
      // O método ToJSONObject transforma a linha atual do Banco em JSON.
      // Detalhe Arquitetural: Campos BLOB (Imagens) são automaticamente
      // convertidos para strings Base64 pelo DataSet.Serialize!
      LJsonPayload := FQueryConsulta.ToJSONObject();

      try
        // 3. Dispara o Payload JSON para a rota da API via POST
        LMemTableResposta.Close;
        // Carrega a resposta da API (JSON) na MemTable para facilitar a leitura
        LMemTableResposta.LoadFromJSON(EnviarPostAPI('/rota-recepcao', LJsonPayload.ToJSON));

        if not LMemTableResposta.IsEmpty then
        begin
          // 4. Valida a resposta do Servidor
          if (LMemTableResposta.FieldByName('STATUS').AsString = 'Sucesso') or
             (LMemTableResposta.FieldByName('STATUS').AsString = 'OK') then
          begin
            // 5. Baixa Local: Se a API gravou, atualiza o status no SQLite para 'S'
            FConexaoLocal.StartTransaction;
            try
              FQueryAtualiza.ParamByName('pID').AsInteger := FQueryConsulta.FieldByName('ID').AsInteger;
              FQueryAtualiza.ParamByName('pSTATUS').AsString := 'S';
              FQueryAtualiza.Execute;

              FConexaoLocal.Commit;
            except
              on E: Exception do
              begin
                FConexaoLocal.Rollback;
                raise Exception.Create('Erro ao confirmar sincronismo local: ' + E.Message);
              end;
            end;
          end;
        end;

      finally
        // Libera o JSON da memória a cada volta do laço para evitar vazamentos
        if Assigned(LJsonPayload) then FreeAndNil(LJsonPayload);
      end;

      FQueryConsulta.Next;
    end;

  finally
    LMemTableResposta.Free;
  end;
end;

end.