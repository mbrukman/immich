import pg from 'pg';

const client = new pg.Client(
  'postgres://postgres:postgres@localhost:5432/immich'
);
let connected = false;

export const db = {
  reset: async () => {
    if (!connected) {
      await client.connect();
    }

    for (const table of ['users', 'system_metadata']) {
      await client.query(`DELETE FROM ${table} CASCADE;`);
    }
  },
  teardown: async () => {
    await client.end();
  },
};
