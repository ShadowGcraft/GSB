
  +------------------------------------------------+
  |   GSB - application de 2013, sans Docker       |
  +------------------------------------------------+

  Premiere execution : telechargement de PHP et MariaDB,
  comptez une dizaine de minutes selon le reseau.

    journal : C:\Users\admin\Documents\GitHub\GSB\legacy\local\log\demarrage.log

==> 1/6  Outils portables
    php déjà présent
    mariadb déjà présent

==> 2/6  Configuration de PHP
    php.ini ecrit, 8 extensions activees : pdo_mysql, mysqli, mbstring, openssl, intl, curl, fileinfo, sodium
    PHP 7.4.33
    extensions indispensables chargees
    7-Zip disponible pour Composer

==> 3/6  Base de données
    un serveur du projet tourne deja sur le port 3310, il est reutilise
    demarrage du serveur sur le port 3310
    mysqld s'est arrete tout seul, code inconnu.

    --- sortie d'erreur de mysqld ---
    2026-09-09 15:24:59 0 [Note] Starting MariaDB 10.6.21-MariaDB source revision 066e8d6aeabc13242193780341e0f845528105de server_uid ebXEijUgqHkZdxUlvO8f0TxOZlM= as process 2380
    2026-09-09 15:24:59 0 [ERROR] InnoDB: The data file './ibdata1' must be writable
    2026-09-09 15:24:59 0 [ERROR] InnoDB: The data file './ibdata1' must be writable
    2026-09-09 15:24:59 0 [ERROR] Plugin 'InnoDB' registration as a STORAGE ENGINE failed.
    2026-09-09 15:24:59 0 [Note] Plugin 'FEEDBACK' is disabled.
    2026-09-09 15:24:59 0 [ERROR] Unknown/unsupported storage engine: InnoDB
    2026-09-09 15:24:59 0 [ERROR] Aborting
    --- fin ---
    (sortie de mysqld : vide)

    --- journal MariaDB (PC-F20X-X.err) ---
    2026-09-09 14:50:47 0 [ERROR] Can't start server: Bind on TCP/IP port. Got error: 10013: Une tentative d’accès à un socket de manière interdite par ses autorisations d’accès a été tentée.


    2026-09-09 14:50:47 0 [ERROR] Do you already have another server running on port: 3307 ?
    2026-09-09 14:50:47 0 [ERROR] Aborting
    2026-09-09 14:54:19 0 [Note] Starting MariaDB 10.6.21-MariaDB source revision 066e8d6aeabc13242193780341e0f845528105de server_uid w6YmbZ5tltey9urkqG68vNeYQME= as process 14492
    2026-09-09 14:54:19 0 [Note] InnoDB: Compressed tables use zlib 1.3.1
    2026-09-09 14:54:19 0 [Note] InnoDB: Number of pools: 1
    2026-09-09 14:54:19 0 [Note] InnoDB: Using crc32 + pclmulqdq instructions
    2026-09-09 14:54:19 0 [Note] InnoDB: Initializing buffer pool, total size = 134217728, chunk size = 134217728
    2026-09-09 14:54:19 0 [Note] InnoDB: Completed initialization of buffer pool
    2026-09-09 14:54:19 0 [Note] InnoDB: 128 rollback segments are active.
    2026-09-09 14:54:19 0 [Note] InnoDB: Creating shared tablespace for temporary tables
    2026-09-09 14:54:19 0 [Note] InnoDB: Setting file './ibtmp1' size to 12 MB. Physically writing the file full; Please wait ...
    2026-09-09 14:54:19 0 [Note] InnoDB: File './ibtmp1' size is now 12 MB.
    2026-09-09 14:54:19 0 [Note] InnoDB: 10.6.21 started; log sequence number 42538; transaction id 14
    2026-09-09 14:54:19 0 [Note] InnoDB: Loading buffer pool(s) from C:\Users\admin\Documents\GitHub\GSB\legacy\local\mysql\data\ib_buffer_pool
    2026-09-09 14:54:19 0 [Note] Plugin 'FEEDBACK' is disabled.
    2026-09-09 14:54:19 0 [Note] InnoDB: Buffer pool(s) load completed at 260909 14:54:19
    2026-09-09 14:54:19 0 [Note] Server socket created on IP: '127.0.0.1'.
    2026-09-09 14:54:19 0 [ERROR] Can't start server: Bind on TCP/IP port. Got error: 10013: Une tentative d’accès à un socket de manière interdite par ses autorisations d’accès a été tentée.


    2026-09-09 14:54:19 0 [ERROR] Do you already have another server running on port: 3307 ?
    2026-09-09 14:54:19 0 [ERROR] Aborting
    --- fin ---

    Les fichiers de donnees sont deja utilises par un autre serveur.
    Un serveur MariaDB de ce projet tourne encore, sans doute
    lance par une execution precedente. Arretez-le :
      .\sans-docker\arreter-windows.ps1
    puis relancez ce script.
    Processus mysqld actuellement en memoire :
      pid 4300  C:\Program Files\MySQL\MySQL Server 8.0\bin\mysqld.exe
      pid 5220  C:\Program Files\MySQL\MySQL Server 8.0\bin\mysqld.exe
      pid 15272  c:\xampp\mysql\bin\mysqld.exe
      pid 15616  C:\Users\admin\Documents\GitHub\GSB\legacy\local\bin\mariadb\mariadb-10.6.21-winx64\bin\mysqld.exe
    Le serveur de base de donnees n'a pas pu demarrer.

    Journal complet : C:\Users\admin\Documents\GitHub\GSB\legacy\local\log\demarrage.log

  ECHEC : les messages ci-dessus indiquent a quelle etape.

Appuyez sur une touche pour continuer...