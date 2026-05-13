import 'package:drift/drift.dart';

import '../database.dart';

class MangaLibraryUserDataDao {
  static Future<List<MangaLibraryUserDataData>> selectAll() {
    return appDb.select(appDb.mangaLibraryUserData).get();
  }

  static Future<MangaLibraryUserDataData?> selectByKey(int gid, String itemType) {
    return (appDb.select(appDb.mangaLibraryUserData)..where((data) => data.gid.equals(gid) & data.itemType.equals(itemType))).getSingleOrNull();
  }

  static Future<int> upsert(MangaLibraryUserDataCompanion userData) {
    return appDb.into(appDb.mangaLibraryUserData).insertOnConflictUpdate(userData);
  }

  static Future<int> updateUserRating(int gid, String itemType, double? userRating) {
    return upsert(
      MangaLibraryUserDataCompanion.insert(
        gid: Value(gid),
        itemType: itemType,
        userRating: Value(userRating),
        updatedAt: DateTime.now().toString(),
      ),
    );
  }

  static Future<int> deleteByKey(int gid, String itemType) {
    return (appDb.delete(appDb.mangaLibraryUserData)..where((data) => data.gid.equals(gid) & data.itemType.equals(itemType))).go();
  }
}
