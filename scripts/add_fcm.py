import sqlite3
conn = sqlite3.connect('db.sqlite3')
cur = conn.cursor()
try:
    cur.execute("ALTER TABLE accounts_caregiver ADD COLUMN fcm_device_token varchar(255);")
    conn.commit()
    print('column-added')
except Exception as e:
    print('error', e)
finally:
    conn.close()
