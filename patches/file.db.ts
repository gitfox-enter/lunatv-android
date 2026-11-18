/* eslint-disable @typescript-eslint/no-explicit-any */
import { promises as fs } from 'fs';
import path from 'path';

import { AdminConfig } from './admin.types';
import { hashPassword, verifyPassword } from './password';
import { Favorite, IStorage, PlayRecord, SkipConfig } from './types';

/**
 * Single-file JSON storage.
 *
 * LunaTV ships with a `localstorage` mode, but that only works for the web UI:
 * the API routes and any native client (Selene) still go through DbManager,
 * which in that mode holds `null` and fails every favourites /
 * playback-record / admin-config call. This backend gives a self-contained
 * server somewhere to put that data — one JSON document inside the app's
 * private directory, no Redis, no database daemon.
 *
 * Every mutation rewrites the document atomically (temp file + rename) so a
 * kill mid-write cannot leave half a file behind.
 */

interface Doc {
  users: { [userName: string]: { password: string } };
  favorites: { [userName: string]: { [key: string]: Favorite } };
  playRecords: { [userName: string]: { [key: string]: PlayRecord } };
  searchHistory: { [userName: string]: string[] };
  skipConfigs: { [userName: string]: { [key: string]: SkipConfig } };
  adminConfig: AdminConfig | null;
}

const EMPTY: Doc = {
  users: {},
  favorites: {},
  playRecords: {},
  searchHistory: {},
  skipConfigs: {},
  adminConfig: null,
};

export class FileStorage implements IStorage {
  private readonly file: string;
  private loaded = false;
  private doc: Doc = JSON.parse(JSON.stringify(EMPTY)) as Doc;
  /** Serialises writes: every mutation appends itself to this chain. */
  private queue: Promise<void> = Promise.resolve();

  constructor() {
    const dir = process.env.DATA_DIR || path.join(process.cwd(), 'data');
    this.file = path.join(dir, 'storage.json');
  }

  private async load(): Promise<Doc> {
    if (this.loaded) {
      return this.doc;
    }
    try {
      const raw = await fs.readFile(this.file, 'utf-8');
      const parsed = JSON.parse(raw) as Partial<Doc>;
      this.doc = { ...JSON.parse(JSON.stringify(EMPTY)), ...parsed } as Doc;
    } catch {
      // First run (or a corrupt file): start empty rather than fail the app.
      this.doc = JSON.parse(JSON.stringify(EMPTY)) as Doc;
    }
    this.loaded = true;
    return this.doc;
  }

  private mutate<T>(fn: (doc: Doc) => T): Promise<T> {
    const run = async (): Promise<T> => {
      const doc = await this.load();
      const result = fn(doc);
      await fs.mkdir(path.dirname(this.file), { recursive: true });
      const tmp = `${this.file}.tmp`;
      await fs.writeFile(tmp, JSON.stringify(doc), 'utf-8');
      await fs.rename(tmp, this.file);
      return result;
    };
    const next = this.queue.then(run, run);
    this.queue = next.then(
      () => undefined,
      () => undefined
    );
    return next;
  }

  private static userBucket<T>(map: { [u: string]: { [k: string]: T } }, user: string) {
    if (!map[user]) {
      map[user] = {};
    }
    return map[user];
  }

  // ---------------------------------------------------------------- play records
  async getPlayRecord(userName: string, key: string): Promise<PlayRecord | null> {
    const doc = await this.load();
    return doc.playRecords[userName]?.[key] ?? null;
  }

  async setPlayRecord(userName: string, key: string, record: PlayRecord): Promise<void> {
    await this.mutate((doc) => {
      FileStorage.userBucket(doc.playRecords, userName)[key] = record;
    });
  }

  async getAllPlayRecords(userName: string): Promise<{ [key: string]: PlayRecord }> {
    const doc = await this.load();
    return doc.playRecords[userName] ?? {};
  }

  async deletePlayRecord(userName: string, key: string): Promise<void> {
    await this.mutate((doc) => {
      delete doc.playRecords[userName]?.[key];
    });
  }

  async deleteAllPlayRecords(userName: string): Promise<void> {
    await this.mutate((doc) => {
      doc.playRecords[userName] = {};
    });
  }

  // ---------------------------------------------------------------- favourites
  async getFavorite(userName: string, key: string): Promise<Favorite | null> {
    const doc = await this.load();
    return doc.favorites[userName]?.[key] ?? null;
  }

  async setFavorite(userName: string, key: string, favorite: Favorite): Promise<void> {
    await this.mutate((doc) => {
      FileStorage.userBucket(doc.favorites, userName)[key] = favorite;
    });
  }

  async getAllFavorites(userName: string): Promise<{ [key: string]: Favorite }> {
    const doc = await this.load();
    return doc.favorites[userName] ?? {};
  }

  async deleteFavorite(userName: string, key: string): Promise<void> {
    await this.mutate((doc) => {
      delete doc.favorites[userName]?.[key];
    });
  }

  async deleteAllFavorites(userName: string): Promise<void> {
    await this.mutate((doc) => {
      doc.favorites[userName] = {};
    });
  }

  // ---------------------------------------------------------------- users
  async registerUser(userName: string, password: string): Promise<void> {
    await this.mutate((doc) => {
      doc.users[userName] = { password: hashPassword(password) };
    });
  }

  async verifyUser(userName: string, password: string): Promise<boolean> {
    const doc = await this.load();
    const user = doc.users[userName];
    return user ? verifyPassword(password, user.password) : false;
  }

  async checkUserExist(userName: string): Promise<boolean> {
    const doc = await this.load();
    return Boolean(doc.users[userName]);
  }

  async changePassword(userName: string, newPassword: string): Promise<void> {
    await this.mutate((doc) => {
      if (doc.users[userName]) {
        doc.users[userName].password = hashPassword(newPassword);
      }
    });
  }

  async deleteUser(userName: string): Promise<void> {
    await this.mutate((doc) => {
      delete doc.users[userName];
      delete doc.favorites[userName];
      delete doc.playRecords[userName];
      delete doc.searchHistory[userName];
      delete doc.skipConfigs[userName];
    });
  }

  async getAllUsers(): Promise<string[]> {
    const doc = await this.load();
    return Object.keys(doc.users);
  }

  // ---------------------------------------------------------------- search history
  async getSearchHistory(userName: string): Promise<string[]> {
    const doc = await this.load();
    return doc.searchHistory[userName] ?? [];
  }

  async addSearchHistory(userName: string, keyword: string): Promise<void> {
    await this.mutate((doc) => {
      const list = doc.searchHistory[userName] ?? [];
      doc.searchHistory[userName] = [keyword, ...list.filter((k) => k !== keyword)].slice(0, 20);
    });
  }

  async deleteSearchHistory(userName: string, keyword?: string): Promise<void> {
    await this.mutate((doc) => {
      if (!keyword) {
        doc.searchHistory[userName] = [];
        return;
      }
      doc.searchHistory[userName] = (doc.searchHistory[userName] ?? []).filter((k) => k !== keyword);
    });
  }

  // ---------------------------------------------------------------- admin config
  async getAdminConfig(): Promise<AdminConfig | null> {
    const doc = await this.load();
    return doc.adminConfig;
  }

  async setAdminConfig(config: AdminConfig): Promise<void> {
    await this.mutate((doc) => {
      doc.adminConfig = config;
    });
  }

  // ---------------------------------------------------------------- skip intro/outro
  async getSkipConfig(userName: string, source: string, id: string): Promise<SkipConfig | null> {
    const doc = await this.load();
    return doc.skipConfigs[userName]?.[`${source}+${id}`] ?? null;
  }

  async setSkipConfig(
    userName: string,
    source: string,
    id: string,
    config: SkipConfig
  ): Promise<void> {
    await this.mutate((doc) => {
      FileStorage.userBucket(doc.skipConfigs, userName)[`${source}+${id}`] = config;
    });
  }

  async deleteSkipConfig(userName: string, source: string, id: string): Promise<void> {
    await this.mutate((doc) => {
      delete doc.skipConfigs[userName]?.[`${source}+${id}`];
    });
  }

  async getAllSkipConfigs(userName: string): Promise<{ [key: string]: SkipConfig }> {
    const doc = await this.load();
    return doc.skipConfigs[userName] ?? {};
  }

  // ---------------------------------------------------------------- maintenance
  async clearAllData(): Promise<void> {
    await this.mutate((doc) => {
      Object.keys(doc).forEach((k) => {
        (doc as any)[k] = (EMPTY as any)[k];
      });
    });
  }
}