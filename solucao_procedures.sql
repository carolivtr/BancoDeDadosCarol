USE Universidade;
GO
CREATE OR ALTER PROCEDURE procMATRICULAALUNO
(
    @NOME  VARCHAR(50),
    @CURSO CHAR(3)
)
AS
BEGIN
    SET NOCOUNT ON;

    -- se o curso nao existe, avisa e para.
    IF NOT EXISTS (SELECT 1 FROM CURSOS WHERE CURSO = @CURSO)
    BEGIN
        RAISERROR('Curso nao encontrado.', 16, 1);
        RETURN;
    END

    DECLARE @MATRICULA INT;

    -- 1) cadastra o aluno
    INSERT ALUNOS (NOME) VALUES (@NOME);

    -- 2) pega o numero da matricula que acabou d ser criada
    SET @MATRICULA = SCOPE_IDENTITY();

    -- 3) matricula o aluno em todas as materias do curso d uma vez,
    -- copiando os dados da tabela MATERIAS
    INSERT MATRICULA (MATRICULA, CURSO, MATERIA, PROFESSOR, PERLETIVO)
    SELECT @MATRICULA, CURSO, SIGLA, PROFESSOR, YEAR(GETDATE())
    FROM MATERIAS
    WHERE CURSO = @CURSO;

    -- 4) resultado
    SELECT * FROM MATRICULA WHERE MATRICULA = @MATRICULA;
END
GO


CREATE OR ALTER PROCEDURE sp_CadastraNotas
(
    @MATRICULA INT,
    @CURSO     CHAR(3),
    @MATERIA   CHAR(3),
    @PERLETIVO CHAR(4),
    @NOTA      FLOAT,
    @FALTA     INT,
    @BIMESTRE  INT
)
AS
BEGIN
    IF @BIMESTRE = 1
    BEGIN
        UPDATE MATRICULA
        SET N1 = @NOTA,
            F1 = @FALTA,
            TOTALPONTOS = @NOTA,
            TOTALFALTAS = @FALTA,
            MEDIA = @NOTA
        WHERE MATRICULA = @MATRICULA
          AND CURSO = @CURSO
          AND MATERIA = @MATERIA
          AND PERLETIVO = @PERLETIVO;
    END
    ELSE IF @BIMESTRE = 2
    BEGIN
        UPDATE MATRICULA
        SET N2 = @NOTA,
            F2 = @FALTA,
            TOTALPONTOS = @NOTA + N1,
            TOTALFALTAS = @FALTA + F1,
            MEDIA = (@NOTA + N1) / 2
        WHERE MATRICULA = @MATRICULA
          AND CURSO = @CURSO
          AND MATERIA = @MATERIA
          AND PERLETIVO = @PERLETIVO;
    END
    ELSE IF @BIMESTRE = 3
    BEGIN
        UPDATE MATRICULA
        SET N3 = @NOTA,
            F3 = @FALTA,
            TOTALPONTOS = @NOTA + N1 + N2,
            TOTALFALTAS = @FALTA + F1 + F2,
            MEDIA = (@NOTA + N1 + N2) / 3
        WHERE MATRICULA = @MATRICULA
          AND CURSO = @CURSO
          AND MATERIA = @MATERIA
          AND PERLETIVO = @PERLETIVO;
    END
    ELSE IF @BIMESTRE = 4
    BEGIN
        DECLARE @FREQ_MINIMA     FLOAT = 75,  -- presenca minima
                @MEDIA_APROVACAO FLOAT = 6,   -- media para aprovar direto
                @MEDIA_EXAME     FLOAT = 4;   -- media minima para poder fazer exame

        DECLARE @RESULTADO   VARCHAR(20),
                @FREQUENCIA  FLOAT,
                @MEDIAFINAL  FLOAT,
                @CARGAHORA   INT,
                @TOTALFALTAS INT;

        -- carga horaria da materia
        SET @CARGAHORA = (SELECT CARGAHORARIA
                          FROM MATERIAS
                          WHERE SIGLA = @MATERIA
                            AND CURSO = @CURSO);

        -- lanca a nota e falta do 4 bimestre e calcula totais e media
        UPDATE MATRICULA
        SET N4 = @NOTA,
            F4 = @FALTA,
            TOTALPONTOS = @NOTA + N1 + N2 + N3,
            TOTALFALTAS = @FALTA + F1 + F2 + F3,
            MEDIA = (@NOTA + N1 + N2 + N3) / 4
        WHERE MATRICULA = @MATRICULA
          AND CURSO = @CURSO
          AND MATERIA = @MATERIA
          AND PERLETIVO = @PERLETIVO;

        --le de volta a media e o total de faltas ja calculados
        SELECT @MEDIAFINAL  = MEDIA,
               @TOTALFALTAS = TOTALFALTAS
        FROM MATRICULA
        WHERE MATRICULA = @MATRICULA
          AND CURSO = @CURSO
          AND MATERIA = @MATERIA
          AND PERLETIVO = @PERLETIVO;

        -- frequencia 
        SET @FREQUENCIA = (@CARGAHORA - @TOTALFALTAS) * 100.0 / @CARGAHORA;

        -- decide o resultado (a falta pesa primeiro pq reprova mesmo com nota boa)
        IF @FREQUENCIA < @FREQ_MINIMA
            SET @RESULTADO = 'REPROVADO POR FALTA';
        ELSE IF @MEDIAFINAL >= @MEDIA_APROVACAO
            SET @RESULTADO = 'APROVADO';
        ELSE IF @MEDIAFINAL >= @MEDIA_EXAME
            SET @RESULTADO = 'EXAME';
        ELSE
            SET @RESULTADO = 'REPROVADO';

        -- frequencia, media final e resultado
        UPDATE MATRICULA
        SET PERCFREQ   = @FREQUENCIA,
            MEDIAFINAL = @MEDIAFINAL,
            RESULTADO  = @RESULTADO
        WHERE MATRICULA = @MATRICULA
          AND CURSO = @CURSO
          AND MATERIA = @MATERIA
          AND PERLETIVO = @PERLETIVO;
    END

    SELECT * FROM MATRICULA WHERE MATRICULA = @MATRICULA;
END
GO


CREATE OR ALTER PROCEDURE sp_LancaExame
(
    @MATRICULA INT,
    @CURSO     CHAR(3),
    @MATERIA   CHAR(3),
    @PERLETIVO CHAR(4),
    @NOTAEXAME FLOAT
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @MEDIA_APOS_EXAME FLOAT = 5;   -- media (anual + exame) para aprovar

    DECLARE @RESULTADO_ATUAL  VARCHAR(20),
            @NOTAEXAME_ATUAL  FLOAT,
            @MEDIA            FLOAT,
            @MEDIAFINAL       FLOAT,
            @NOVO_RESULTADO   VARCHAR(20);

    IF @NOTAEXAME < 0 OR @NOTAEXAME > 10
    BEGIN
        RAISERROR('A nota do exame deve estar entre 0 e 10.', 16, 1);
        RETURN;
    END

    -- aq busca a situacao atual do aluno nessa materia
    SELECT @RESULTADO_ATUAL = RESULTADO,
           @NOTAEXAME_ATUAL = NOTAEXAME,
           @MEDIA           = MEDIA
    FROM MATRICULA
    WHERE MATRICULA = @MATRICULA
      AND CURSO = @CURSO
      AND MATERIA = @MATERIA
      AND PERLETIVO = @PERLETIVO;

    IF @@ROWCOUNT = 0
    BEGIN
        RAISERROR('Matricula nao encontrada.', 16, 1);
        RETURN;
    END

    -- so pode lancar exame quem esta em exame ou quem ja fez e precisa corrigir a nota
    IF ISNULL(@RESULTADO_ATUAL, '') <> 'EXAME' AND @NOTAEXAME_ATUAL IS NULL
    BEGIN
        RAISERROR('Este aluno nao esta em exame nesta materia.', 16, 1);
        RETURN;
    END

    -- media entre a media anual e a nota do exame
    SET @MEDIAFINAL = (@MEDIA + @NOTAEXAME) / 2;

    IF @MEDIAFINAL >= @MEDIA_APOS_EXAME
        SET @NOVO_RESULTADO = 'APROVADO';
    ELSE
        SET @NOVO_RESULTADO = 'REPROVADO';

    UPDATE MATRICULA
    SET NOTAEXAME  = @NOTAEXAME,
        MEDIAFINAL = @MEDIAFINAL,
        RESULTADO  = @NOVO_RESULTADO
    WHERE MATRICULA = @MATRICULA
      AND CURSO = @CURSO
      AND MATERIA = @MATERIA
      AND PERLETIVO = @PERLETIVO;

    SELECT * FROM MATRICULA
    WHERE MATRICULA = @MATRICULA
      AND CURSO = @CURSO
      AND MATERIA = @MATERIA
      AND PERLETIVO = @PERLETIVO;
END
GO
