<?php
/*
 * Sessions PHP dans MariaDB (F4-S12, CHG-3412) : partagées entre les réplicas de Legacy-RDV.
 * Ajout. Aucune extension PHP supplémentaire : mysqli seulement (déjà utilisé par l'application).
 *
 * Table (sql/V2__sessions.sql, créée par le compte de migration) :
 *   sessions(id VARCHAR(128) PK, donnees MEDIUMBLOB, expire_le INT UNSIGNED, KEY(expire_le))
 * Le verrouillage par session de PHP « files » n'existe plus : deux requêtes simultanées d'un même
 * navigateur peuvent s'écraser leurs données de session. Acceptable ici (jeton CSRF et message flash
 * seulement) ; écrit dans l'ADR des choix (CHG-3412).
 */

final class SessionsBase implements SessionHandlerInterface
{
    public function __construct(private mysqli $db, private int $duree)
    {
    }

    public function open(string $path, string $name): bool
    {
        return true;
    }

    public function close(): bool
    {
        return true;
    }

    public function read(string $id): string|false
    {
        $req = $this->db->prepare('SELECT donnees FROM sessions WHERE id = ? AND expire_le > ?');
        $maintenant = time();
        $req->bind_param('si', $id, $maintenant);
        $req->execute();
        $ligne = $req->get_result()->fetch_row();
        return $ligne === null ? '' : (string) $ligne[0];
    }

    public function write(string $id, string $data): bool
    {
        $req = $this->db->prepare(
            'INSERT INTO sessions (id, donnees, expire_le) VALUES (?, ?, ?)
             ON DUPLICATE KEY UPDATE donnees = VALUES(donnees), expire_le = VALUES(expire_le)'
        );
        $expire = time() + $this->duree;
        $req->bind_param('ssi', $id, $data, $expire);
        return $req->execute();
    }

    public function destroy(string $id): bool
    {
        $req = $this->db->prepare('DELETE FROM sessions WHERE id = ?');
        $req->bind_param('s', $id);
        return $req->execute();
    }

    public function gc(int $max_lifetime): int|false
    {
        // Le ménage est fait par la tâche de purge (CronJob) ; session.gc_probability = 0 dans l'image.
        $req = $this->db->prepare('DELETE FROM sessions WHERE expire_le < ?');
        $maintenant = time();
        $req->bind_param('i', $maintenant);
        $req->execute();
        return $req->affected_rows;
    }
}
