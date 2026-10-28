EXEC sp_CadastraNotas @MATRICULA = 1,      -- int
                      @CURSO = 'ENG',      -- char(3)
                      @MATERIA = 'BDA',    -- char(3)
                      @PERLETIVO = '2025', -- char(4)
                      @NOTA = 7.0,         -- float
                      @FALTA = 2,
                      @BIMESTRE = 1      -- int
          