import 'package:drift/drift.dart';

@TableIndex(name: 'mlu_idx_updated_at', columns: {#updatedAt})
class MangaLibraryUserData extends Table {
  @override
  String? get tableName => 'manga_library_user_data';

  IntColumn get gid => integer()();

  TextColumn get itemType => text()();

  RealColumn get userRating => real().nullable()();

  TextColumn get updatedAt => text()();

  @override
  Set<Column<Object>>? get primaryKey => {gid, itemType};
}
