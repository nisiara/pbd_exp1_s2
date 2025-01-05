--ALTER SESSION SET NLS_TERRITORY = 'CHILE';
--ALTER SESSION SET NLS_LANGUAGE = 'SPANISH';

VAR b_periodo_proceso VARCHAR2(10);
EXEC :b_periodo_proceso := '032024';

DECLARE
    v_iteracion_clientes NUMBER := 0;
    v_total_clientes NUMBER;
    
    v_cliente_id_primero Cliente.id_cli%TYPE;
    v_cliente_id_ultimo Cliente.id_cli%TYPE;
    
    v_cliente_rut Cliente.numrun_cli%TYPE;
    v_cliente_nombre VARCHAR2(90);
    v_cliente_edad NUMBER(10,0);
    
    v_cliente_renta Cliente.renta%TYPE;
    v_cliente_comuna Comuna.nombre_comuna%TYPE;
    v_cliente_tipo Tipo_Cliente.nombre_tipo_cli%TYPE;
    
    v_cliente_puntaje NUMBER(5);
    
    v_tramo_min Tramo_Edad.sec_tramo_edad%TYPE;
    v_tramo_max Tramo_Edad.sec_tramo_edad%TYPE;
    
    v_tramo_porcentaje Tramo_Edad.porcentaje%TYPE;
    v_edad_tramo_min Tramo_Edad.tramo_inf%TYPE;
    v_edad_tramo_max Tramo_Edad.tramo_sup%TYPE;
    
    v_cliente_correo VARCHAR(100);
    
BEGIN
    
    /*
    Ejecutamos la instrucción Truncate para limpiar la tabla antes de repoblarla con nuevos datos.
    */
    EXECUTE IMMEDIATE 'TRUNCATE TABLE DETALLE_DE_CLIENTES';
    
    /*
    Obtener el total de clientes para poder comparar su valor con la variable v_iteracion_clientes
    y realizar la confirmación o rollback de la transacción.
    */
    SELECT
        COUNT(id_cli)
    INTO v_total_clientes
    FROM
        Cliente;
    
    /*
    Obtener rangos mínimo y máximo para la iteración de Clientes
    */
    SELECT
         MIN(id_cli)
        ,MAX(id_cli)
    INTO v_cliente_id_primero, v_cliente_id_ultimo
    FROM Cliente;
    
    /* 
    Calcular edad Cliente.
    */
    SELECT 
         MIN(sec_tramo_edad)
        ,MAX(sec_tramo_edad)
    INTO v_tramo_min, v_tramo_max
    FROM
        Tramo_Edad
    WHERE
        anno_vig = EXTRACT(YEAR FROM SYSDATE);
    
    WHILE v_cliente_id_primero <= v_cliente_id_ultimo LOOP
    
        /*
         Instrucciones para obtener el ID, concatenar el nombre (apellido paterno, apellido materno y primer nombre)
         y calcular la edad del cliente.
        */
        SELECT 
             numrun_cli
            ,INITCAP(appaterno_cli || ' ' || apmaterno_cli || ' ' || pnombre_cli)
            ,ROUND((SYSDATE - fecha_nac_cli) / 365.25)
            
        INTO v_cliente_rut, v_cliente_nombre, v_cliente_edad
        FROM 
            Cliente
        WHERE 
            id_cli = v_cliente_id_primero;
            
            
        --CALCULAR PUNTAJE CLIENTE
        /*
        PROFE: En el documento de las instrucciones aparece un punto que dice lo siguiente:
        'Para efectos de actividad, deberás ejecutar su proceso calculando los puntajes de todos los clientes del periodo de marzo 2024.'
        Si se hace con el 2024, no se dan los resultados que aparecen en la Figura 3. Hay que hacerlo con el año 2025.
        Por ejemplo Miguel Uval Riquelme, el primer cliente de la tabla, cae en el caso donde se debe calcular su puntaje desde la tabla
        Tramo_Edad, el tiene 53 años. Si usamos los rangos del 2024 debería 0, al usar el 2025 sí está dentro de un rago para calcular 
        su puntaje dado un porcentaje.
        */
        SELECT 
             co.nombre_comuna
            ,cli.renta
            ,tcli.nombre_tipo_cli
        INTO v_cliente_comuna, v_cliente_renta, v_cliente_tipo
        FROM
            Cliente cli
        INNER JOIN Comuna co ON cli.id_comuna = co.id_comuna
        INNER JOIN Tipo_Cliente tcli ON cli.id_tipo_cli = tcli.id_tipo_cli
        WHERE 
            id_cli = v_cliente_id_primero;
            
        IF v_cliente_comuna NOT IN ('La Reina', 'Las Condes', 'Vitacura') AND v_cliente_renta > 700000 THEN
            v_cliente_puntaje := v_cliente_renta * 0.03;
        ELSIF v_cliente_tipo IN ('VIP', 'Extranjero') THEN
            v_cliente_puntaje := v_cliente_edad * 30;
        ELSE
            v_cliente_puntaje := 0;
        END IF;
        
        /*
        Los clientes que caes dentro del caso donde se debe calcular su puntaje a través de la tabla Tramo_Edad,
        hice un ciclo para que iterara cada fila de tabla verificando, dependiendo de la edad del cliente, que porcentaje
        se le debía asignar y con este valor calcular el puntaje correspondiente.
        */
        IF v_cliente_puntaje = 0 THEN
            FOR i IN v_tramo_min..v_tramo_max LOOP
                SELECT 
                    tramo_inf
                    ,tramo_sup
                    ,porcentaje
                INTO v_edad_tramo_min, v_edad_tramo_max, v_tramo_porcentaje
                FROM
                    Tramo_Edad
                WHERE
                    anno_vig = EXTRACT(YEAR FROM SYSDATE) AND
                    sec_tramo_edad = i;
                    
                IF v_cliente_edad BETWEEN v_edad_tramo_min AND v_edad_tramo_max THEN
                    v_cliente_puntaje := v_cliente_renta * (v_tramo_porcentaje / 100);
                    EXIT;
                END IF;
            END LOOP;
        END IF;
        
        
        --CREAR CORREO ELECTRONICO
        SELECT 
            LOWER(appaterno_cli) || v_cliente_edad || '*' || SUBSTR(pnombre_cli, 1, 1) || 
            TO_CHAR(fecha_nac_cli, 'DD') || SUBSTR(:b_periodo_proceso, 2, 1) || '@LogiCarg.cl'
        INTO v_cliente_correo
        FROM
            Cliente
         WHERE 
            id_cli = v_cliente_id_primero; 
        
        /* 
        Verificar algunos de los valores obtenidos por el calculo y manipulacion de información. 
        */
        --DBMS_OUTPUT.PUT_LINE( v_cliente_nombre || ' ' || v_cliente_edad || ' ' ||v_cliente_puntaje || ' ' || v_cliente_correo);

        INSERT INTO DETALLE_DE_CLIENTES 
            VALUES (
                v_cliente_id_primero
                ,v_cliente_rut
                ,v_cliente_nombre
                ,v_cliente_edad
                ,v_cliente_puntaje
                ,v_cliente_correo
                ,SUBSTR(:b_periodo_proceso, 1, 2) ||'/'|| SUBSTR(:b_periodo_proceso, 3, 4)
            );
               
        v_cliente_id_primero := v_cliente_id_primero + 5;
        v_iteracion_clientes := v_iteracion_clientes + 1;
    END LOOP;
    
    DBMS_OUTPUT.PUT_LINE('PROCESANDO CLIENTES');
    IF v_iteracion_clientes = v_total_clientes THEN
        DBMS_OUTPUT.PUT_LINE('Proceso Finalizado Exitosamente');
        DBMS_OUTPUT.PUT_LINE('Se Procesaron: ' || v_total_clientes || ' ' || 'CLIENTES.');
        COMMIT;
    ELSE
        ROLLBACK;
    END IF;
END;

--SELECT * FROM Detalle_De_Clientes ORDER BY 1;
 
       