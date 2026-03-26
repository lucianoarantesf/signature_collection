unit uAssinaturaExemplo;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  System.Generics.Collections,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Objects,
  FireDAC.Comp.Client, FireDAC.Stan.Param, Data.DB;

type
  // 1. Estrutura de dados para armazenar a geometria do traço
  TAssinatura = Record
    PosicaoCursor: TPointF;
    PosState: Byte; // 0 = Início, 1 = Movimento, 2 = Fim do traço
  End;

type
  TFormAssinaturaExemplo = class(TForm)
    RectangleAssinatura: TRectangle; // Área de desenho
    ImageAssinatura: TImage;         // Container invisível para receber o Screenshot
    
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure RectangleAssinaturaMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
    procedure RectangleAssinaturaMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    procedure RectangleAssinaturaPaint(Sender: TObject; Canvas: TCanvas; const ARect: TRectF);
  private
    Assina: TList<TAssinatura>;
    FBotaoPressionado: Boolean;

    procedure AddPoint(const X, Y: Single; const state: Byte; Rect: TRectangle);
    procedure SalvarAssinaturaBanco; // Simula a gravação no SQLite
  public
    { Public declarations }
  end;

var
  FormAssinaturaExemplo: TFormAssinaturaExemplo;

implementation

{$R *.fmx}

{ TFormAssinaturaExemplo }

procedure TFormAssinaturaExemplo.FormCreate(Sender: TObject);
begin
  // Instancia a lista genérica que vai segurar as coordenadas na memória RAM
  Assina := TList<TAssinatura>.Create;
  FBotaoPressionado := False;
end;

procedure TFormAssinaturaExemplo.FormDestroy(Sender: TObject);
begin
  FreeAndNil(Assina);
end;

// =============================================================================
// CAPTURA VETORIAL DOS PONTOS
// =============================================================================
procedure TFormAssinaturaExemplo.AddPoint(const X, Y: Single; const state: Byte; Rect: TRectangle);
var
  p: TAssinatura;
begin
  p.PosicaoCursor := PointF(X, Y);
  p.PosState := state;

  if Assina.Count - 1 < 0 then
    p.PosState := 0;

  // Filtro de otimização: Só armazena o ponto se houve um deslocamento real > 0.8
  if p.PosState <> 1 then
    Assina.Add(p)
  else if p.PosicaoCursor.Distance(Assina.Last.PosicaoCursor) > 0.8 then
    Assina.Add(p);

  // Força o motor gráfico do FMX a redesenhar o componente com o novo ponto
  Rect.Repaint;
end;

procedure TFormAssinaturaExemplo.RectangleAssinaturaMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
begin
  // Rastrea o dedo/mouse enquanto pressionado
  if ssLeft in Shift then
  begin
    if NOT FBotaoPressionado then
    begin
      AddPoint(X, Y, 0, RectangleAssinatura);
      FBotaoPressionado := True;
    end
    else
      AddPoint(X, Y, 1, RectangleAssinatura);
  end;
end;

procedure TFormAssinaturaExemplo.RectangleAssinaturaMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  // Finaliza o traço atual quando o usuário solta o dedo
  FBotaoPressionado := False;
  AddPoint(X, Y, 2, RectangleAssinatura);
end;

// =============================================================================
// MOTOR DE RENDERIZAÇÃO GRÁFICA
// =============================================================================
procedure TFormAssinaturaExemplo.RectangleAssinaturaPaint(Sender: TObject; Canvas: TCanvas; const ARect: TRectF);
var
  p: TAssinatura;
  p1, p2: TPointF;
begin
  if NOT (Assina.Count - 1 > 0) then exit;

  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Dash := TStrokeDash.Solid;
  Canvas.Stroke.Thickness := 4; // Espessura da "Caneta"
  Canvas.Stroke.Color := TAlphaColorRec.Darkblue;

  // Percorre a lista conectando os pontos para formar a assinatura
  for p in Assina do
  begin
    case p.PosState of
      0: p1 := p.PosicaoCursor;
      1, 2:
        begin
          p2 := p.PosicaoCursor;
          Canvas.DrawLine(p1, p2, 1, Canvas.Stroke);
          p1 := p.PosicaoCursor;
        end;
    end;
  end;
end;

// =============================================================================
// EXTRAÇÃO E PERSISTÊNCIA (OFFLINE-FIRST)
// =============================================================================
procedure TFormAssinaturaExemplo.SalvarAssinaturaBanco;
var
  LStream: TMemoryStream;
  LQuery: TFDQuery;
begin
  if not Assigned(ImageAssinatura) then exit;

  // 1. Transforma o componente desenhado em uma Imagem real (Bitmap)
  ImageAssinatura.Bitmap.Assign(RectangleAssinatura.MakeScreenshot);

  LStream := TMemoryStream.Create;
  LQuery := TFDQuery.Create(nil);
  try
    try
      // LQuery.Connection := ConexaoLocalSQLite; // (Comentado para o exemplo compilar)
      
      // 2. Transfere os pixels para a memória em formato compacto
      ImageAssinatura.Bitmap.SaveToStream(LStream);
      LStream.Position := 0;

      // 3. Prepara a Query
      LQuery.SQL.Add('INSERT INTO TABELA_ASSINATURAS (ASSINATURA_BLOB, STATUS_SYNC) VALUES (:pBLOB, ''N'')');
      
      // 4. Injeta a imagem com ftBlob para evitar Invalid Pointer Operation
      LQuery.ParamByName('pBLOB').LoadFromStream(LStream, ftBlob);
      
      // LQuery.ExecSQL; // (Comentado para o exemplo compilar isolado)

      ShowMessage('Captura e gravação simuladas com sucesso!');
    except
      on E: Exception do
        ShowMessage('Erro na arquitetura de salvamento: ' + E.Message);
    end;
  finally
    // 5. Faxina de Memória RAM Essencial para Android/iOS
    LStream.Free;
    LQuery.Free;
    Assina.Clear;
    RectangleAssinatura.Repaint;
    
    // Libera a memória de vídeo do TImage invisível
    if not ImageAssinatura.Bitmap.IsEmpty then
      ImageAssinatura.Bitmap.Assign(nil);
  end;
end;

end.