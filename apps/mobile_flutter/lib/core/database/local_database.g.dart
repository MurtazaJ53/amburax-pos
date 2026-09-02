// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_database.dart';

// ignore_for_file: type=lint
class $ShopSettingsEntriesTable extends ShopSettingsEntries
    with TableInfo<$ShopSettingsEntriesTable, ShopSettingsEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ShopSettingsEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'shop_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<ShopSettingsEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  ShopSettingsEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ShopSettingsEntry(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ShopSettingsEntriesTable createAlias(String alias) {
    return $ShopSettingsEntriesTable(attachedDatabase, alias);
  }
}

class ShopSettingsEntry extends DataClass
    implements Insertable<ShopSettingsEntry> {
  final String key;
  final String value;
  final int updatedAt;
  const ShopSettingsEntry({
    required this.key,
    required this.value,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  ShopSettingsEntriesCompanion toCompanion(bool nullToAbsent) {
    return ShopSettingsEntriesCompanion(
      key: Value(key),
      value: Value(value),
      updatedAt: Value(updatedAt),
    );
  }

  factory ShopSettingsEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ShopSettingsEntry(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  ShopSettingsEntry copyWith({String? key, String? value, int? updatedAt}) =>
      ShopSettingsEntry(
        key: key ?? this.key,
        value: value ?? this.value,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  ShopSettingsEntry copyWithCompanion(ShopSettingsEntriesCompanion data) {
    return ShopSettingsEntry(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ShopSettingsEntry(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ShopSettingsEntry &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAt == this.updatedAt);
}

class ShopSettingsEntriesCompanion extends UpdateCompanion<ShopSettingsEntry> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const ShopSettingsEntriesCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ShopSettingsEntriesCompanion.insert({
    required String key,
    required String value,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value),
       updatedAt = Value(updatedAt);
  static Insertable<ShopSettingsEntry> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ShopSettingsEntriesCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return ShopSettingsEntriesCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ShopSettingsEntriesCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $InventoryEntriesTable extends InventoryEntries
    with TableInfo<$InventoryEntriesTable, InventoryEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InventoryEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _priceMeta = const VerificationMeta('price');
  @override
  late final GeneratedColumn<double> price = GeneratedColumn<double>(
    'price',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _skuMeta = const VerificationMeta('sku');
  @override
  late final GeneratedColumn<String> sku = GeneratedColumn<String>(
    'sku',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _barcodeMeta = const VerificationMeta(
    'barcode',
  );
  @override
  late final GeneratedColumn<String> barcode = GeneratedColumn<String>(
    'barcode',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('General'),
  );
  static const VerificationMeta _subcategoryMeta = const VerificationMeta(
    'subcategory',
  );
  @override
  late final GeneratedColumn<String> subcategory = GeneratedColumn<String>(
    'subcategory',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<String> size = GeneratedColumn<String>(
    'size',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hsnCodeMeta = const VerificationMeta(
    'hsnCode',
  );
  @override
  late final GeneratedColumn<String> hsnCode = GeneratedColumn<String>(
    'hsn_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _gstRateMeta = const VerificationMeta(
    'gstRate',
  );
  @override
  late final GeneratedColumn<double> gstRate = GeneratedColumn<double>(
    'gst_rate',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _priceIncludesTaxMeta = const VerificationMeta(
    'priceIncludesTax',
  );
  @override
  late final GeneratedColumn<bool> priceIncludesTax = GeneratedColumn<bool>(
    'price_includes_tax',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("price_includes_tax" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _stockMeta = const VerificationMeta('stock');
  @override
  late final GeneratedColumn<double> stock = GeneratedColumn<double>(
    'stock',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sourceMetaMeta = const VerificationMeta(
    'sourceMeta',
  );
  @override
  late final GeneratedColumn<String> sourceMeta = GeneratedColumn<String>(
    'source_meta',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _imagePathMeta = const VerificationMeta(
    'imagePath',
  );
  @override
  late final GeneratedColumn<String> imagePath = GeneratedColumn<String>(
    'image_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unitMeta = const VerificationMeta('unit');
  @override
  late final GeneratedColumn<String> unit = GeneratedColumn<String>(
    'unit',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reorderLevelMeta = const VerificationMeta(
    'reorderLevel',
  );
  @override
  late final GeneratedColumn<int> reorderLevel = GeneratedColumn<int>(
    'reorder_level',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hasStockHistoryMeta = const VerificationMeta(
    'hasStockHistory',
  );
  @override
  late final GeneratedColumn<bool> hasStockHistory = GeneratedColumn<bool>(
    'has_stock_history',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("has_stock_history" IN (0, 1))',
    ),
  );
  static const VerificationMeta _variantGroupIdMeta = const VerificationMeta(
    'variantGroupId',
  );
  @override
  late final GeneratedColumn<String> variantGroupId = GeneratedColumn<String>(
    'variant_group_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _variantLabelMeta = const VerificationMeta(
    'variantLabel',
  );
  @override
  late final GeneratedColumn<String> variantLabel = GeneratedColumn<String>(
    'variant_label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _tombstoneMeta = const VerificationMeta(
    'tombstone',
  );
  @override
  late final GeneratedColumn<bool> tombstone = GeneratedColumn<bool>(
    'tombstone',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("tombstone" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    price,
    sku,
    barcode,
    category,
    subcategory,
    size,
    description,
    hsnCode,
    gstRate,
    priceIncludesTax,
    stock,
    sourceMeta,
    imagePath,
    unit,
    reorderLevel,
    hasStockHistory,
    variantGroupId,
    variantLabel,
    createdAt,
    updatedAt,
    tombstone,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'inventory';
  @override
  VerificationContext validateIntegrity(
    Insertable<InventoryEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('price')) {
      context.handle(
        _priceMeta,
        price.isAcceptableOrUnknown(data['price']!, _priceMeta),
      );
    } else if (isInserting) {
      context.missing(_priceMeta);
    }
    if (data.containsKey('sku')) {
      context.handle(
        _skuMeta,
        sku.isAcceptableOrUnknown(data['sku']!, _skuMeta),
      );
    }
    if (data.containsKey('barcode')) {
      context.handle(
        _barcodeMeta,
        barcode.isAcceptableOrUnknown(data['barcode']!, _barcodeMeta),
      );
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    }
    if (data.containsKey('subcategory')) {
      context.handle(
        _subcategoryMeta,
        subcategory.isAcceptableOrUnknown(
          data['subcategory']!,
          _subcategoryMeta,
        ),
      );
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('hsn_code')) {
      context.handle(
        _hsnCodeMeta,
        hsnCode.isAcceptableOrUnknown(data['hsn_code']!, _hsnCodeMeta),
      );
    }
    if (data.containsKey('gst_rate')) {
      context.handle(
        _gstRateMeta,
        gstRate.isAcceptableOrUnknown(data['gst_rate']!, _gstRateMeta),
      );
    }
    if (data.containsKey('price_includes_tax')) {
      context.handle(
        _priceIncludesTaxMeta,
        priceIncludesTax.isAcceptableOrUnknown(
          data['price_includes_tax']!,
          _priceIncludesTaxMeta,
        ),
      );
    }
    if (data.containsKey('stock')) {
      context.handle(
        _stockMeta,
        stock.isAcceptableOrUnknown(data['stock']!, _stockMeta),
      );
    }
    if (data.containsKey('source_meta')) {
      context.handle(
        _sourceMetaMeta,
        sourceMeta.isAcceptableOrUnknown(data['source_meta']!, _sourceMetaMeta),
      );
    }
    if (data.containsKey('image_path')) {
      context.handle(
        _imagePathMeta,
        imagePath.isAcceptableOrUnknown(data['image_path']!, _imagePathMeta),
      );
    }
    if (data.containsKey('unit')) {
      context.handle(
        _unitMeta,
        unit.isAcceptableOrUnknown(data['unit']!, _unitMeta),
      );
    }
    if (data.containsKey('reorder_level')) {
      context.handle(
        _reorderLevelMeta,
        reorderLevel.isAcceptableOrUnknown(
          data['reorder_level']!,
          _reorderLevelMeta,
        ),
      );
    }
    if (data.containsKey('has_stock_history')) {
      context.handle(
        _hasStockHistoryMeta,
        hasStockHistory.isAcceptableOrUnknown(
          data['has_stock_history']!,
          _hasStockHistoryMeta,
        ),
      );
    }
    if (data.containsKey('variant_group_id')) {
      context.handle(
        _variantGroupIdMeta,
        variantGroupId.isAcceptableOrUnknown(
          data['variant_group_id']!,
          _variantGroupIdMeta,
        ),
      );
    }
    if (data.containsKey('variant_label')) {
      context.handle(
        _variantLabelMeta,
        variantLabel.isAcceptableOrUnknown(
          data['variant_label']!,
          _variantLabelMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('tombstone')) {
      context.handle(
        _tombstoneMeta,
        tombstone.isAcceptableOrUnknown(data['tombstone']!, _tombstoneMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  InventoryEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InventoryEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      price: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}price'],
      )!,
      sku: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sku'],
      ),
      barcode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}barcode'],
      ),
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      subcategory: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subcategory'],
      ),
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}size'],
      ),
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      hsnCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hsn_code'],
      ),
      gstRate: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}gst_rate'],
      )!,
      priceIncludesTax: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}price_includes_tax'],
      )!,
      stock: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}stock'],
      )!,
      sourceMeta: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_meta'],
      ),
      imagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_path'],
      ),
      unit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit'],
      ),
      reorderLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reorder_level'],
      ),
      hasStockHistory: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}has_stock_history'],
      ),
      variantGroupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}variant_group_id'],
      ),
      variantLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}variant_label'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      tombstone: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}tombstone'],
      )!,
    );
  }

  @override
  $InventoryEntriesTable createAlias(String alias) {
    return $InventoryEntriesTable(attachedDatabase, alias);
  }
}

class InventoryEntry extends DataClass implements Insertable<InventoryEntry> {
  final String id;
  final String name;
  final double price;
  final String? sku;

  /// The EAN/UPC printed on the packet, from the backend's `barcode`.
  ///
  /// Separate from [sku] on purpose, because they are different things: the
  /// SKU is the shop's own code and the barcode is the manufacturer's. The
  /// phone used to have only the SKU, so a product whose barcode differed
  /// from its SKU could not be scanned at all.
  final String? barcode;
  final String category;
  final String? subcategory;
  final String? size;
  final String? description;
  final String? hsnCode;
  final double gstRate;
  final bool priceIncludesTax;
  final double stock;
  final String? sourceMeta;
  final String? imagePath;
  final String? unit;
  final int? reorderLevel;

  /// Whether this item has ever been given stock, from the backend's
  /// `has_stock_history`. Null means the server did not say — an older
  /// deployment, or a row written before this column existed. Null is not
  /// false: treating "unknown" as "never stocked" would label a shelf holding
  /// 462 units as untracked, which is the mistake the web already made and
  /// wrote a comment about.
  final bool? hasStockHistory;
  final String? variantGroupId;
  final String? variantLabel;
  final int createdAt;
  final int updatedAt;
  final bool tombstone;
  const InventoryEntry({
    required this.id,
    required this.name,
    required this.price,
    this.sku,
    this.barcode,
    required this.category,
    this.subcategory,
    this.size,
    this.description,
    this.hsnCode,
    required this.gstRate,
    required this.priceIncludesTax,
    required this.stock,
    this.sourceMeta,
    this.imagePath,
    this.unit,
    this.reorderLevel,
    this.hasStockHistory,
    this.variantGroupId,
    this.variantLabel,
    required this.createdAt,
    required this.updatedAt,
    required this.tombstone,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['price'] = Variable<double>(price);
    if (!nullToAbsent || sku != null) {
      map['sku'] = Variable<String>(sku);
    }
    if (!nullToAbsent || barcode != null) {
      map['barcode'] = Variable<String>(barcode);
    }
    map['category'] = Variable<String>(category);
    if (!nullToAbsent || subcategory != null) {
      map['subcategory'] = Variable<String>(subcategory);
    }
    if (!nullToAbsent || size != null) {
      map['size'] = Variable<String>(size);
    }
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || hsnCode != null) {
      map['hsn_code'] = Variable<String>(hsnCode);
    }
    map['gst_rate'] = Variable<double>(gstRate);
    map['price_includes_tax'] = Variable<bool>(priceIncludesTax);
    map['stock'] = Variable<double>(stock);
    if (!nullToAbsent || sourceMeta != null) {
      map['source_meta'] = Variable<String>(sourceMeta);
    }
    if (!nullToAbsent || imagePath != null) {
      map['image_path'] = Variable<String>(imagePath);
    }
    if (!nullToAbsent || unit != null) {
      map['unit'] = Variable<String>(unit);
    }
    if (!nullToAbsent || reorderLevel != null) {
      map['reorder_level'] = Variable<int>(reorderLevel);
    }
    if (!nullToAbsent || hasStockHistory != null) {
      map['has_stock_history'] = Variable<bool>(hasStockHistory);
    }
    if (!nullToAbsent || variantGroupId != null) {
      map['variant_group_id'] = Variable<String>(variantGroupId);
    }
    if (!nullToAbsent || variantLabel != null) {
      map['variant_label'] = Variable<String>(variantLabel);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    map['tombstone'] = Variable<bool>(tombstone);
    return map;
  }

  InventoryEntriesCompanion toCompanion(bool nullToAbsent) {
    return InventoryEntriesCompanion(
      id: Value(id),
      name: Value(name),
      price: Value(price),
      sku: sku == null && nullToAbsent ? const Value.absent() : Value(sku),
      barcode: barcode == null && nullToAbsent
          ? const Value.absent()
          : Value(barcode),
      category: Value(category),
      subcategory: subcategory == null && nullToAbsent
          ? const Value.absent()
          : Value(subcategory),
      size: size == null && nullToAbsent ? const Value.absent() : Value(size),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      hsnCode: hsnCode == null && nullToAbsent
          ? const Value.absent()
          : Value(hsnCode),
      gstRate: Value(gstRate),
      priceIncludesTax: Value(priceIncludesTax),
      stock: Value(stock),
      sourceMeta: sourceMeta == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceMeta),
      imagePath: imagePath == null && nullToAbsent
          ? const Value.absent()
          : Value(imagePath),
      unit: unit == null && nullToAbsent ? const Value.absent() : Value(unit),
      reorderLevel: reorderLevel == null && nullToAbsent
          ? const Value.absent()
          : Value(reorderLevel),
      hasStockHistory: hasStockHistory == null && nullToAbsent
          ? const Value.absent()
          : Value(hasStockHistory),
      variantGroupId: variantGroupId == null && nullToAbsent
          ? const Value.absent()
          : Value(variantGroupId),
      variantLabel: variantLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(variantLabel),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      tombstone: Value(tombstone),
    );
  }

  factory InventoryEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InventoryEntry(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      price: serializer.fromJson<double>(json['price']),
      sku: serializer.fromJson<String?>(json['sku']),
      barcode: serializer.fromJson<String?>(json['barcode']),
      category: serializer.fromJson<String>(json['category']),
      subcategory: serializer.fromJson<String?>(json['subcategory']),
      size: serializer.fromJson<String?>(json['size']),
      description: serializer.fromJson<String?>(json['description']),
      hsnCode: serializer.fromJson<String?>(json['hsnCode']),
      gstRate: serializer.fromJson<double>(json['gstRate']),
      priceIncludesTax: serializer.fromJson<bool>(json['priceIncludesTax']),
      stock: serializer.fromJson<double>(json['stock']),
      sourceMeta: serializer.fromJson<String?>(json['sourceMeta']),
      imagePath: serializer.fromJson<String?>(json['imagePath']),
      unit: serializer.fromJson<String?>(json['unit']),
      reorderLevel: serializer.fromJson<int?>(json['reorderLevel']),
      hasStockHistory: serializer.fromJson<bool?>(json['hasStockHistory']),
      variantGroupId: serializer.fromJson<String?>(json['variantGroupId']),
      variantLabel: serializer.fromJson<String?>(json['variantLabel']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      tombstone: serializer.fromJson<bool>(json['tombstone']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'price': serializer.toJson<double>(price),
      'sku': serializer.toJson<String?>(sku),
      'barcode': serializer.toJson<String?>(barcode),
      'category': serializer.toJson<String>(category),
      'subcategory': serializer.toJson<String?>(subcategory),
      'size': serializer.toJson<String?>(size),
      'description': serializer.toJson<String?>(description),
      'hsnCode': serializer.toJson<String?>(hsnCode),
      'gstRate': serializer.toJson<double>(gstRate),
      'priceIncludesTax': serializer.toJson<bool>(priceIncludesTax),
      'stock': serializer.toJson<double>(stock),
      'sourceMeta': serializer.toJson<String?>(sourceMeta),
      'imagePath': serializer.toJson<String?>(imagePath),
      'unit': serializer.toJson<String?>(unit),
      'reorderLevel': serializer.toJson<int?>(reorderLevel),
      'hasStockHistory': serializer.toJson<bool?>(hasStockHistory),
      'variantGroupId': serializer.toJson<String?>(variantGroupId),
      'variantLabel': serializer.toJson<String?>(variantLabel),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'tombstone': serializer.toJson<bool>(tombstone),
    };
  }

  InventoryEntry copyWith({
    String? id,
    String? name,
    double? price,
    Value<String?> sku = const Value.absent(),
    Value<String?> barcode = const Value.absent(),
    String? category,
    Value<String?> subcategory = const Value.absent(),
    Value<String?> size = const Value.absent(),
    Value<String?> description = const Value.absent(),
    Value<String?> hsnCode = const Value.absent(),
    double? gstRate,
    bool? priceIncludesTax,
    double? stock,
    Value<String?> sourceMeta = const Value.absent(),
    Value<String?> imagePath = const Value.absent(),
    Value<String?> unit = const Value.absent(),
    Value<int?> reorderLevel = const Value.absent(),
    Value<bool?> hasStockHistory = const Value.absent(),
    Value<String?> variantGroupId = const Value.absent(),
    Value<String?> variantLabel = const Value.absent(),
    int? createdAt,
    int? updatedAt,
    bool? tombstone,
  }) => InventoryEntry(
    id: id ?? this.id,
    name: name ?? this.name,
    price: price ?? this.price,
    sku: sku.present ? sku.value : this.sku,
    barcode: barcode.present ? barcode.value : this.barcode,
    category: category ?? this.category,
    subcategory: subcategory.present ? subcategory.value : this.subcategory,
    size: size.present ? size.value : this.size,
    description: description.present ? description.value : this.description,
    hsnCode: hsnCode.present ? hsnCode.value : this.hsnCode,
    gstRate: gstRate ?? this.gstRate,
    priceIncludesTax: priceIncludesTax ?? this.priceIncludesTax,
    stock: stock ?? this.stock,
    sourceMeta: sourceMeta.present ? sourceMeta.value : this.sourceMeta,
    imagePath: imagePath.present ? imagePath.value : this.imagePath,
    unit: unit.present ? unit.value : this.unit,
    reorderLevel: reorderLevel.present ? reorderLevel.value : this.reorderLevel,
    hasStockHistory: hasStockHistory.present
        ? hasStockHistory.value
        : this.hasStockHistory,
    variantGroupId: variantGroupId.present
        ? variantGroupId.value
        : this.variantGroupId,
    variantLabel: variantLabel.present ? variantLabel.value : this.variantLabel,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    tombstone: tombstone ?? this.tombstone,
  );
  InventoryEntry copyWithCompanion(InventoryEntriesCompanion data) {
    return InventoryEntry(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      price: data.price.present ? data.price.value : this.price,
      sku: data.sku.present ? data.sku.value : this.sku,
      barcode: data.barcode.present ? data.barcode.value : this.barcode,
      category: data.category.present ? data.category.value : this.category,
      subcategory: data.subcategory.present
          ? data.subcategory.value
          : this.subcategory,
      size: data.size.present ? data.size.value : this.size,
      description: data.description.present
          ? data.description.value
          : this.description,
      hsnCode: data.hsnCode.present ? data.hsnCode.value : this.hsnCode,
      gstRate: data.gstRate.present ? data.gstRate.value : this.gstRate,
      priceIncludesTax: data.priceIncludesTax.present
          ? data.priceIncludesTax.value
          : this.priceIncludesTax,
      stock: data.stock.present ? data.stock.value : this.stock,
      sourceMeta: data.sourceMeta.present
          ? data.sourceMeta.value
          : this.sourceMeta,
      imagePath: data.imagePath.present ? data.imagePath.value : this.imagePath,
      unit: data.unit.present ? data.unit.value : this.unit,
      reorderLevel: data.reorderLevel.present
          ? data.reorderLevel.value
          : this.reorderLevel,
      hasStockHistory: data.hasStockHistory.present
          ? data.hasStockHistory.value
          : this.hasStockHistory,
      variantGroupId: data.variantGroupId.present
          ? data.variantGroupId.value
          : this.variantGroupId,
      variantLabel: data.variantLabel.present
          ? data.variantLabel.value
          : this.variantLabel,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      tombstone: data.tombstone.present ? data.tombstone.value : this.tombstone,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InventoryEntry(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('price: $price, ')
          ..write('sku: $sku, ')
          ..write('barcode: $barcode, ')
          ..write('category: $category, ')
          ..write('subcategory: $subcategory, ')
          ..write('size: $size, ')
          ..write('description: $description, ')
          ..write('hsnCode: $hsnCode, ')
          ..write('gstRate: $gstRate, ')
          ..write('priceIncludesTax: $priceIncludesTax, ')
          ..write('stock: $stock, ')
          ..write('sourceMeta: $sourceMeta, ')
          ..write('imagePath: $imagePath, ')
          ..write('unit: $unit, ')
          ..write('reorderLevel: $reorderLevel, ')
          ..write('hasStockHistory: $hasStockHistory, ')
          ..write('variantGroupId: $variantGroupId, ')
          ..write('variantLabel: $variantLabel, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('tombstone: $tombstone')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    name,
    price,
    sku,
    barcode,
    category,
    subcategory,
    size,
    description,
    hsnCode,
    gstRate,
    priceIncludesTax,
    stock,
    sourceMeta,
    imagePath,
    unit,
    reorderLevel,
    hasStockHistory,
    variantGroupId,
    variantLabel,
    createdAt,
    updatedAt,
    tombstone,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InventoryEntry &&
          other.id == this.id &&
          other.name == this.name &&
          other.price == this.price &&
          other.sku == this.sku &&
          other.barcode == this.barcode &&
          other.category == this.category &&
          other.subcategory == this.subcategory &&
          other.size == this.size &&
          other.description == this.description &&
          other.hsnCode == this.hsnCode &&
          other.gstRate == this.gstRate &&
          other.priceIncludesTax == this.priceIncludesTax &&
          other.stock == this.stock &&
          other.sourceMeta == this.sourceMeta &&
          other.imagePath == this.imagePath &&
          other.unit == this.unit &&
          other.reorderLevel == this.reorderLevel &&
          other.hasStockHistory == this.hasStockHistory &&
          other.variantGroupId == this.variantGroupId &&
          other.variantLabel == this.variantLabel &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.tombstone == this.tombstone);
}

class InventoryEntriesCompanion extends UpdateCompanion<InventoryEntry> {
  final Value<String> id;
  final Value<String> name;
  final Value<double> price;
  final Value<String?> sku;
  final Value<String?> barcode;
  final Value<String> category;
  final Value<String?> subcategory;
  final Value<String?> size;
  final Value<String?> description;
  final Value<String?> hsnCode;
  final Value<double> gstRate;
  final Value<bool> priceIncludesTax;
  final Value<double> stock;
  final Value<String?> sourceMeta;
  final Value<String?> imagePath;
  final Value<String?> unit;
  final Value<int?> reorderLevel;
  final Value<bool?> hasStockHistory;
  final Value<String?> variantGroupId;
  final Value<String?> variantLabel;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<bool> tombstone;
  final Value<int> rowid;
  const InventoryEntriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.price = const Value.absent(),
    this.sku = const Value.absent(),
    this.barcode = const Value.absent(),
    this.category = const Value.absent(),
    this.subcategory = const Value.absent(),
    this.size = const Value.absent(),
    this.description = const Value.absent(),
    this.hsnCode = const Value.absent(),
    this.gstRate = const Value.absent(),
    this.priceIncludesTax = const Value.absent(),
    this.stock = const Value.absent(),
    this.sourceMeta = const Value.absent(),
    this.imagePath = const Value.absent(),
    this.unit = const Value.absent(),
    this.reorderLevel = const Value.absent(),
    this.hasStockHistory = const Value.absent(),
    this.variantGroupId = const Value.absent(),
    this.variantLabel = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.tombstone = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InventoryEntriesCompanion.insert({
    required String id,
    required String name,
    required double price,
    this.sku = const Value.absent(),
    this.barcode = const Value.absent(),
    this.category = const Value.absent(),
    this.subcategory = const Value.absent(),
    this.size = const Value.absent(),
    this.description = const Value.absent(),
    this.hsnCode = const Value.absent(),
    this.gstRate = const Value.absent(),
    this.priceIncludesTax = const Value.absent(),
    this.stock = const Value.absent(),
    this.sourceMeta = const Value.absent(),
    this.imagePath = const Value.absent(),
    this.unit = const Value.absent(),
    this.reorderLevel = const Value.absent(),
    this.hasStockHistory = const Value.absent(),
    this.variantGroupId = const Value.absent(),
    this.variantLabel = const Value.absent(),
    required int createdAt,
    this.updatedAt = const Value.absent(),
    this.tombstone = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       price = Value(price),
       createdAt = Value(createdAt);
  static Insertable<InventoryEntry> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<double>? price,
    Expression<String>? sku,
    Expression<String>? barcode,
    Expression<String>? category,
    Expression<String>? subcategory,
    Expression<String>? size,
    Expression<String>? description,
    Expression<String>? hsnCode,
    Expression<double>? gstRate,
    Expression<bool>? priceIncludesTax,
    Expression<double>? stock,
    Expression<String>? sourceMeta,
    Expression<String>? imagePath,
    Expression<String>? unit,
    Expression<int>? reorderLevel,
    Expression<bool>? hasStockHistory,
    Expression<String>? variantGroupId,
    Expression<String>? variantLabel,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<bool>? tombstone,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (price != null) 'price': price,
      if (sku != null) 'sku': sku,
      if (barcode != null) 'barcode': barcode,
      if (category != null) 'category': category,
      if (subcategory != null) 'subcategory': subcategory,
      if (size != null) 'size': size,
      if (description != null) 'description': description,
      if (hsnCode != null) 'hsn_code': hsnCode,
      if (gstRate != null) 'gst_rate': gstRate,
      if (priceIncludesTax != null) 'price_includes_tax': priceIncludesTax,
      if (stock != null) 'stock': stock,
      if (sourceMeta != null) 'source_meta': sourceMeta,
      if (imagePath != null) 'image_path': imagePath,
      if (unit != null) 'unit': unit,
      if (reorderLevel != null) 'reorder_level': reorderLevel,
      if (hasStockHistory != null) 'has_stock_history': hasStockHistory,
      if (variantGroupId != null) 'variant_group_id': variantGroupId,
      if (variantLabel != null) 'variant_label': variantLabel,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (tombstone != null) 'tombstone': tombstone,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InventoryEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<double>? price,
    Value<String?>? sku,
    Value<String?>? barcode,
    Value<String>? category,
    Value<String?>? subcategory,
    Value<String?>? size,
    Value<String?>? description,
    Value<String?>? hsnCode,
    Value<double>? gstRate,
    Value<bool>? priceIncludesTax,
    Value<double>? stock,
    Value<String?>? sourceMeta,
    Value<String?>? imagePath,
    Value<String?>? unit,
    Value<int?>? reorderLevel,
    Value<bool?>? hasStockHistory,
    Value<String?>? variantGroupId,
    Value<String?>? variantLabel,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<bool>? tombstone,
    Value<int>? rowid,
  }) {
    return InventoryEntriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      price: price ?? this.price,
      sku: sku ?? this.sku,
      barcode: barcode ?? this.barcode,
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      size: size ?? this.size,
      description: description ?? this.description,
      hsnCode: hsnCode ?? this.hsnCode,
      gstRate: gstRate ?? this.gstRate,
      priceIncludesTax: priceIncludesTax ?? this.priceIncludesTax,
      stock: stock ?? this.stock,
      sourceMeta: sourceMeta ?? this.sourceMeta,
      imagePath: imagePath ?? this.imagePath,
      unit: unit ?? this.unit,
      reorderLevel: reorderLevel ?? this.reorderLevel,
      hasStockHistory: hasStockHistory ?? this.hasStockHistory,
      variantGroupId: variantGroupId ?? this.variantGroupId,
      variantLabel: variantLabel ?? this.variantLabel,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      tombstone: tombstone ?? this.tombstone,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (price.present) {
      map['price'] = Variable<double>(price.value);
    }
    if (sku.present) {
      map['sku'] = Variable<String>(sku.value);
    }
    if (barcode.present) {
      map['barcode'] = Variable<String>(barcode.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (subcategory.present) {
      map['subcategory'] = Variable<String>(subcategory.value);
    }
    if (size.present) {
      map['size'] = Variable<String>(size.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (hsnCode.present) {
      map['hsn_code'] = Variable<String>(hsnCode.value);
    }
    if (gstRate.present) {
      map['gst_rate'] = Variable<double>(gstRate.value);
    }
    if (priceIncludesTax.present) {
      map['price_includes_tax'] = Variable<bool>(priceIncludesTax.value);
    }
    if (stock.present) {
      map['stock'] = Variable<double>(stock.value);
    }
    if (sourceMeta.present) {
      map['source_meta'] = Variable<String>(sourceMeta.value);
    }
    if (imagePath.present) {
      map['image_path'] = Variable<String>(imagePath.value);
    }
    if (unit.present) {
      map['unit'] = Variable<String>(unit.value);
    }
    if (reorderLevel.present) {
      map['reorder_level'] = Variable<int>(reorderLevel.value);
    }
    if (hasStockHistory.present) {
      map['has_stock_history'] = Variable<bool>(hasStockHistory.value);
    }
    if (variantGroupId.present) {
      map['variant_group_id'] = Variable<String>(variantGroupId.value);
    }
    if (variantLabel.present) {
      map['variant_label'] = Variable<String>(variantLabel.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (tombstone.present) {
      map['tombstone'] = Variable<bool>(tombstone.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InventoryEntriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('price: $price, ')
          ..write('sku: $sku, ')
          ..write('barcode: $barcode, ')
          ..write('category: $category, ')
          ..write('subcategory: $subcategory, ')
          ..write('size: $size, ')
          ..write('description: $description, ')
          ..write('hsnCode: $hsnCode, ')
          ..write('gstRate: $gstRate, ')
          ..write('priceIncludesTax: $priceIncludesTax, ')
          ..write('stock: $stock, ')
          ..write('sourceMeta: $sourceMeta, ')
          ..write('imagePath: $imagePath, ')
          ..write('unit: $unit, ')
          ..write('reorderLevel: $reorderLevel, ')
          ..write('hasStockHistory: $hasStockHistory, ')
          ..write('variantGroupId: $variantGroupId, ')
          ..write('variantLabel: $variantLabel, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('tombstone: $tombstone, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $InventoryPrivateEntriesTable extends InventoryPrivateEntries
    with TableInfo<$InventoryPrivateEntriesTable, InventoryPrivateEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InventoryPrivateEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _costPriceMeta = const VerificationMeta(
    'costPrice',
  );
  @override
  late final GeneratedColumn<double> costPrice = GeneratedColumn<double>(
    'cost_price',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _supplierIdMeta = const VerificationMeta(
    'supplierId',
  );
  @override
  late final GeneratedColumn<String> supplierId = GeneratedColumn<String>(
    'supplier_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastPurchaseDateMeta = const VerificationMeta(
    'lastPurchaseDate',
  );
  @override
  late final GeneratedColumn<String> lastPurchaseDate = GeneratedColumn<String>(
    'last_purchase_date',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _tombstoneMeta = const VerificationMeta(
    'tombstone',
  );
  @override
  late final GeneratedColumn<bool> tombstone = GeneratedColumn<bool>(
    'tombstone',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("tombstone" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    costPrice,
    supplierId,
    lastPurchaseDate,
    updatedAt,
    tombstone,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'inventory_private';
  @override
  VerificationContext validateIntegrity(
    Insertable<InventoryPrivateEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('cost_price')) {
      context.handle(
        _costPriceMeta,
        costPrice.isAcceptableOrUnknown(data['cost_price']!, _costPriceMeta),
      );
    }
    if (data.containsKey('supplier_id')) {
      context.handle(
        _supplierIdMeta,
        supplierId.isAcceptableOrUnknown(data['supplier_id']!, _supplierIdMeta),
      );
    }
    if (data.containsKey('last_purchase_date')) {
      context.handle(
        _lastPurchaseDateMeta,
        lastPurchaseDate.isAcceptableOrUnknown(
          data['last_purchase_date']!,
          _lastPurchaseDateMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('tombstone')) {
      context.handle(
        _tombstoneMeta,
        tombstone.isAcceptableOrUnknown(data['tombstone']!, _tombstoneMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  InventoryPrivateEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InventoryPrivateEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      costPrice: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}cost_price'],
      )!,
      supplierId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}supplier_id'],
      ),
      lastPurchaseDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_purchase_date'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      tombstone: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}tombstone'],
      )!,
    );
  }

  @override
  $InventoryPrivateEntriesTable createAlias(String alias) {
    return $InventoryPrivateEntriesTable(attachedDatabase, alias);
  }
}

class InventoryPrivateEntry extends DataClass
    implements Insertable<InventoryPrivateEntry> {
  final String id;
  final double costPrice;
  final String? supplierId;
  final String? lastPurchaseDate;
  final int updatedAt;
  final bool tombstone;
  const InventoryPrivateEntry({
    required this.id,
    required this.costPrice,
    this.supplierId,
    this.lastPurchaseDate,
    required this.updatedAt,
    required this.tombstone,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['cost_price'] = Variable<double>(costPrice);
    if (!nullToAbsent || supplierId != null) {
      map['supplier_id'] = Variable<String>(supplierId);
    }
    if (!nullToAbsent || lastPurchaseDate != null) {
      map['last_purchase_date'] = Variable<String>(lastPurchaseDate);
    }
    map['updated_at'] = Variable<int>(updatedAt);
    map['tombstone'] = Variable<bool>(tombstone);
    return map;
  }

  InventoryPrivateEntriesCompanion toCompanion(bool nullToAbsent) {
    return InventoryPrivateEntriesCompanion(
      id: Value(id),
      costPrice: Value(costPrice),
      supplierId: supplierId == null && nullToAbsent
          ? const Value.absent()
          : Value(supplierId),
      lastPurchaseDate: lastPurchaseDate == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPurchaseDate),
      updatedAt: Value(updatedAt),
      tombstone: Value(tombstone),
    );
  }

  factory InventoryPrivateEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InventoryPrivateEntry(
      id: serializer.fromJson<String>(json['id']),
      costPrice: serializer.fromJson<double>(json['costPrice']),
      supplierId: serializer.fromJson<String?>(json['supplierId']),
      lastPurchaseDate: serializer.fromJson<String?>(json['lastPurchaseDate']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      tombstone: serializer.fromJson<bool>(json['tombstone']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'costPrice': serializer.toJson<double>(costPrice),
      'supplierId': serializer.toJson<String?>(supplierId),
      'lastPurchaseDate': serializer.toJson<String?>(lastPurchaseDate),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'tombstone': serializer.toJson<bool>(tombstone),
    };
  }

  InventoryPrivateEntry copyWith({
    String? id,
    double? costPrice,
    Value<String?> supplierId = const Value.absent(),
    Value<String?> lastPurchaseDate = const Value.absent(),
    int? updatedAt,
    bool? tombstone,
  }) => InventoryPrivateEntry(
    id: id ?? this.id,
    costPrice: costPrice ?? this.costPrice,
    supplierId: supplierId.present ? supplierId.value : this.supplierId,
    lastPurchaseDate: lastPurchaseDate.present
        ? lastPurchaseDate.value
        : this.lastPurchaseDate,
    updatedAt: updatedAt ?? this.updatedAt,
    tombstone: tombstone ?? this.tombstone,
  );
  InventoryPrivateEntry copyWithCompanion(
    InventoryPrivateEntriesCompanion data,
  ) {
    return InventoryPrivateEntry(
      id: data.id.present ? data.id.value : this.id,
      costPrice: data.costPrice.present ? data.costPrice.value : this.costPrice,
      supplierId: data.supplierId.present
          ? data.supplierId.value
          : this.supplierId,
      lastPurchaseDate: data.lastPurchaseDate.present
          ? data.lastPurchaseDate.value
          : this.lastPurchaseDate,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      tombstone: data.tombstone.present ? data.tombstone.value : this.tombstone,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InventoryPrivateEntry(')
          ..write('id: $id, ')
          ..write('costPrice: $costPrice, ')
          ..write('supplierId: $supplierId, ')
          ..write('lastPurchaseDate: $lastPurchaseDate, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('tombstone: $tombstone')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    costPrice,
    supplierId,
    lastPurchaseDate,
    updatedAt,
    tombstone,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InventoryPrivateEntry &&
          other.id == this.id &&
          other.costPrice == this.costPrice &&
          other.supplierId == this.supplierId &&
          other.lastPurchaseDate == this.lastPurchaseDate &&
          other.updatedAt == this.updatedAt &&
          other.tombstone == this.tombstone);
}

class InventoryPrivateEntriesCompanion
    extends UpdateCompanion<InventoryPrivateEntry> {
  final Value<String> id;
  final Value<double> costPrice;
  final Value<String?> supplierId;
  final Value<String?> lastPurchaseDate;
  final Value<int> updatedAt;
  final Value<bool> tombstone;
  final Value<int> rowid;
  const InventoryPrivateEntriesCompanion({
    this.id = const Value.absent(),
    this.costPrice = const Value.absent(),
    this.supplierId = const Value.absent(),
    this.lastPurchaseDate = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.tombstone = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InventoryPrivateEntriesCompanion.insert({
    required String id,
    this.costPrice = const Value.absent(),
    this.supplierId = const Value.absent(),
    this.lastPurchaseDate = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.tombstone = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id);
  static Insertable<InventoryPrivateEntry> custom({
    Expression<String>? id,
    Expression<double>? costPrice,
    Expression<String>? supplierId,
    Expression<String>? lastPurchaseDate,
    Expression<int>? updatedAt,
    Expression<bool>? tombstone,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (costPrice != null) 'cost_price': costPrice,
      if (supplierId != null) 'supplier_id': supplierId,
      if (lastPurchaseDate != null) 'last_purchase_date': lastPurchaseDate,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (tombstone != null) 'tombstone': tombstone,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InventoryPrivateEntriesCompanion copyWith({
    Value<String>? id,
    Value<double>? costPrice,
    Value<String?>? supplierId,
    Value<String?>? lastPurchaseDate,
    Value<int>? updatedAt,
    Value<bool>? tombstone,
    Value<int>? rowid,
  }) {
    return InventoryPrivateEntriesCompanion(
      id: id ?? this.id,
      costPrice: costPrice ?? this.costPrice,
      supplierId: supplierId ?? this.supplierId,
      lastPurchaseDate: lastPurchaseDate ?? this.lastPurchaseDate,
      updatedAt: updatedAt ?? this.updatedAt,
      tombstone: tombstone ?? this.tombstone,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (costPrice.present) {
      map['cost_price'] = Variable<double>(costPrice.value);
    }
    if (supplierId.present) {
      map['supplier_id'] = Variable<String>(supplierId.value);
    }
    if (lastPurchaseDate.present) {
      map['last_purchase_date'] = Variable<String>(lastPurchaseDate.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (tombstone.present) {
      map['tombstone'] = Variable<bool>(tombstone.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InventoryPrivateEntriesCompanion(')
          ..write('id: $id, ')
          ..write('costPrice: $costPrice, ')
          ..write('supplierId: $supplierId, ')
          ..write('lastPurchaseDate: $lastPurchaseDate, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('tombstone: $tombstone, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SalesEntriesTable extends SalesEntries
    with TableInfo<$SalesEntriesTable, SalesEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SalesEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _totalMeta = const VerificationMeta('total');
  @override
  late final GeneratedColumn<double> total = GeneratedColumn<double>(
    'total',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _discountMeta = const VerificationMeta(
    'discount',
  );
  @override
  late final GeneratedColumn<double> discount = GeneratedColumn<double>(
    'discount',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _discountTypeMeta = const VerificationMeta(
    'discountType',
  );
  @override
  late final GeneratedColumn<String> discountType = GeneratedColumn<String>(
    'discount_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('fixed'),
  );
  static const VerificationMeta _paymentModeMeta = const VerificationMeta(
    'paymentMode',
  );
  @override
  late final GeneratedColumn<String> paymentMode = GeneratedColumn<String>(
    'payment_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('CASH'),
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _customerNameMeta = const VerificationMeta(
    'customerName',
  );
  @override
  late final GeneratedColumn<String> customerName = GeneratedColumn<String>(
    'customer_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _customerPhoneMeta = const VerificationMeta(
    'customerPhone',
  );
  @override
  late final GeneratedColumn<String> customerPhone = GeneratedColumn<String>(
    'customer_phone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _customerIdMeta = const VerificationMeta(
    'customerId',
  );
  @override
  late final GeneratedColumn<String> customerId = GeneratedColumn<String>(
    'customer_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _footerNoteMeta = const VerificationMeta(
    'footerNote',
  );
  @override
  late final GeneratedColumn<String> footerNote = GeneratedColumn<String>(
    'footer_note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _itemsJsonMeta = const VerificationMeta(
    'itemsJson',
  );
  @override
  late final GeneratedColumn<String> itemsJson = GeneratedColumn<String>(
    'items_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _paymentsJsonMeta = const VerificationMeta(
    'paymentsJson',
  );
  @override
  late final GeneratedColumn<String> paymentsJson = GeneratedColumn<String>(
    'payments_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _commandIdMeta = const VerificationMeta(
    'commandId',
  );
  @override
  late final GeneratedColumn<String> commandId = GeneratedColumn<String>(
    'command_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('local_only'),
  );
  static const VerificationMeta _backendReceiptIdMeta = const VerificationMeta(
    'backendReceiptId',
  );
  @override
  late final GeneratedColumn<String> backendReceiptId = GeneratedColumn<String>(
    'backend_receipt_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _backendSaleIdMeta = const VerificationMeta(
    'backendSaleId',
  );
  @override
  late final GeneratedColumn<String> backendSaleId = GeneratedColumn<String>(
    'backend_sale_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSyncErrorMeta = const VerificationMeta(
    'lastSyncError',
  );
  @override
  late final GeneratedColumn<String> lastSyncError = GeneratedColumn<String>(
    'last_sync_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSyncedAtMeta = const VerificationMeta(
    'lastSyncedAt',
  );
  @override
  late final GeneratedColumn<int> lastSyncedAt = GeneratedColumn<int>(
    'last_synced_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tombstoneMeta = const VerificationMeta(
    'tombstone',
  );
  @override
  late final GeneratedColumn<bool> tombstone = GeneratedColumn<bool>(
    'tombstone',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("tombstone" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    total,
    discount,
    discountType,
    paymentMode,
    date,
    createdAt,
    updatedAt,
    customerName,
    customerPhone,
    customerId,
    footerNote,
    itemsJson,
    paymentsJson,
    commandId,
    syncStatus,
    backendReceiptId,
    backendSaleId,
    lastSyncError,
    lastSyncedAt,
    tombstone,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sales';
  @override
  VerificationContext validateIntegrity(
    Insertable<SalesEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('total')) {
      context.handle(
        _totalMeta,
        total.isAcceptableOrUnknown(data['total']!, _totalMeta),
      );
    } else if (isInserting) {
      context.missing(_totalMeta);
    }
    if (data.containsKey('discount')) {
      context.handle(
        _discountMeta,
        discount.isAcceptableOrUnknown(data['discount']!, _discountMeta),
      );
    }
    if (data.containsKey('discount_type')) {
      context.handle(
        _discountTypeMeta,
        discountType.isAcceptableOrUnknown(
          data['discount_type']!,
          _discountTypeMeta,
        ),
      );
    }
    if (data.containsKey('payment_mode')) {
      context.handle(
        _paymentModeMeta,
        paymentMode.isAcceptableOrUnknown(
          data['payment_mode']!,
          _paymentModeMeta,
        ),
      );
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('customer_name')) {
      context.handle(
        _customerNameMeta,
        customerName.isAcceptableOrUnknown(
          data['customer_name']!,
          _customerNameMeta,
        ),
      );
    }
    if (data.containsKey('customer_phone')) {
      context.handle(
        _customerPhoneMeta,
        customerPhone.isAcceptableOrUnknown(
          data['customer_phone']!,
          _customerPhoneMeta,
        ),
      );
    }
    if (data.containsKey('customer_id')) {
      context.handle(
        _customerIdMeta,
        customerId.isAcceptableOrUnknown(data['customer_id']!, _customerIdMeta),
      );
    }
    if (data.containsKey('footer_note')) {
      context.handle(
        _footerNoteMeta,
        footerNote.isAcceptableOrUnknown(data['footer_note']!, _footerNoteMeta),
      );
    }
    if (data.containsKey('items_json')) {
      context.handle(
        _itemsJsonMeta,
        itemsJson.isAcceptableOrUnknown(data['items_json']!, _itemsJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_itemsJsonMeta);
    }
    if (data.containsKey('payments_json')) {
      context.handle(
        _paymentsJsonMeta,
        paymentsJson.isAcceptableOrUnknown(
          data['payments_json']!,
          _paymentsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_paymentsJsonMeta);
    }
    if (data.containsKey('command_id')) {
      context.handle(
        _commandIdMeta,
        commandId.isAcceptableOrUnknown(data['command_id']!, _commandIdMeta),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    if (data.containsKey('backend_receipt_id')) {
      context.handle(
        _backendReceiptIdMeta,
        backendReceiptId.isAcceptableOrUnknown(
          data['backend_receipt_id']!,
          _backendReceiptIdMeta,
        ),
      );
    }
    if (data.containsKey('backend_sale_id')) {
      context.handle(
        _backendSaleIdMeta,
        backendSaleId.isAcceptableOrUnknown(
          data['backend_sale_id']!,
          _backendSaleIdMeta,
        ),
      );
    }
    if (data.containsKey('last_sync_error')) {
      context.handle(
        _lastSyncErrorMeta,
        lastSyncError.isAcceptableOrUnknown(
          data['last_sync_error']!,
          _lastSyncErrorMeta,
        ),
      );
    }
    if (data.containsKey('last_synced_at')) {
      context.handle(
        _lastSyncedAtMeta,
        lastSyncedAt.isAcceptableOrUnknown(
          data['last_synced_at']!,
          _lastSyncedAtMeta,
        ),
      );
    }
    if (data.containsKey('tombstone')) {
      context.handle(
        _tombstoneMeta,
        tombstone.isAcceptableOrUnknown(data['tombstone']!, _tombstoneMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SalesEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SalesEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      total: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}total'],
      )!,
      discount: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}discount'],
      )!,
      discountType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}discount_type'],
      )!,
      paymentMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payment_mode'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      customerName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}customer_name'],
      ),
      customerPhone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}customer_phone'],
      ),
      customerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}customer_id'],
      ),
      footerNote: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}footer_note'],
      ),
      itemsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}items_json'],
      )!,
      paymentsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payments_json'],
      )!,
      commandId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}command_id'],
      ),
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_status'],
      )!,
      backendReceiptId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}backend_receipt_id'],
      ),
      backendSaleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}backend_sale_id'],
      ),
      lastSyncError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_sync_error'],
      ),
      lastSyncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_synced_at'],
      ),
      tombstone: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}tombstone'],
      )!,
    );
  }

  @override
  $SalesEntriesTable createAlias(String alias) {
    return $SalesEntriesTable(attachedDatabase, alias);
  }
}

class SalesEntry extends DataClass implements Insertable<SalesEntry> {
  final String id;
  final double total;
  final double discount;
  final String discountType;
  final String paymentMode;
  final String date;
  final int createdAt;
  final int updatedAt;
  final String? customerName;
  final String? customerPhone;
  final String? customerId;
  final String? footerNote;
  final String itemsJson;
  final String paymentsJson;
  final String? commandId;
  final String syncStatus;
  final String? backendReceiptId;
  final String? backendSaleId;
  final String? lastSyncError;
  final int? lastSyncedAt;
  final bool tombstone;
  const SalesEntry({
    required this.id,
    required this.total,
    required this.discount,
    required this.discountType,
    required this.paymentMode,
    required this.date,
    required this.createdAt,
    required this.updatedAt,
    this.customerName,
    this.customerPhone,
    this.customerId,
    this.footerNote,
    required this.itemsJson,
    required this.paymentsJson,
    this.commandId,
    required this.syncStatus,
    this.backendReceiptId,
    this.backendSaleId,
    this.lastSyncError,
    this.lastSyncedAt,
    required this.tombstone,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['total'] = Variable<double>(total);
    map['discount'] = Variable<double>(discount);
    map['discount_type'] = Variable<String>(discountType);
    map['payment_mode'] = Variable<String>(paymentMode);
    map['date'] = Variable<String>(date);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || customerName != null) {
      map['customer_name'] = Variable<String>(customerName);
    }
    if (!nullToAbsent || customerPhone != null) {
      map['customer_phone'] = Variable<String>(customerPhone);
    }
    if (!nullToAbsent || customerId != null) {
      map['customer_id'] = Variable<String>(customerId);
    }
    if (!nullToAbsent || footerNote != null) {
      map['footer_note'] = Variable<String>(footerNote);
    }
    map['items_json'] = Variable<String>(itemsJson);
    map['payments_json'] = Variable<String>(paymentsJson);
    if (!nullToAbsent || commandId != null) {
      map['command_id'] = Variable<String>(commandId);
    }
    map['sync_status'] = Variable<String>(syncStatus);
    if (!nullToAbsent || backendReceiptId != null) {
      map['backend_receipt_id'] = Variable<String>(backendReceiptId);
    }
    if (!nullToAbsent || backendSaleId != null) {
      map['backend_sale_id'] = Variable<String>(backendSaleId);
    }
    if (!nullToAbsent || lastSyncError != null) {
      map['last_sync_error'] = Variable<String>(lastSyncError);
    }
    if (!nullToAbsent || lastSyncedAt != null) {
      map['last_synced_at'] = Variable<int>(lastSyncedAt);
    }
    map['tombstone'] = Variable<bool>(tombstone);
    return map;
  }

  SalesEntriesCompanion toCompanion(bool nullToAbsent) {
    return SalesEntriesCompanion(
      id: Value(id),
      total: Value(total),
      discount: Value(discount),
      discountType: Value(discountType),
      paymentMode: Value(paymentMode),
      date: Value(date),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      customerName: customerName == null && nullToAbsent
          ? const Value.absent()
          : Value(customerName),
      customerPhone: customerPhone == null && nullToAbsent
          ? const Value.absent()
          : Value(customerPhone),
      customerId: customerId == null && nullToAbsent
          ? const Value.absent()
          : Value(customerId),
      footerNote: footerNote == null && nullToAbsent
          ? const Value.absent()
          : Value(footerNote),
      itemsJson: Value(itemsJson),
      paymentsJson: Value(paymentsJson),
      commandId: commandId == null && nullToAbsent
          ? const Value.absent()
          : Value(commandId),
      syncStatus: Value(syncStatus),
      backendReceiptId: backendReceiptId == null && nullToAbsent
          ? const Value.absent()
          : Value(backendReceiptId),
      backendSaleId: backendSaleId == null && nullToAbsent
          ? const Value.absent()
          : Value(backendSaleId),
      lastSyncError: lastSyncError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncError),
      lastSyncedAt: lastSyncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncedAt),
      tombstone: Value(tombstone),
    );
  }

  factory SalesEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SalesEntry(
      id: serializer.fromJson<String>(json['id']),
      total: serializer.fromJson<double>(json['total']),
      discount: serializer.fromJson<double>(json['discount']),
      discountType: serializer.fromJson<String>(json['discountType']),
      paymentMode: serializer.fromJson<String>(json['paymentMode']),
      date: serializer.fromJson<String>(json['date']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      customerName: serializer.fromJson<String?>(json['customerName']),
      customerPhone: serializer.fromJson<String?>(json['customerPhone']),
      customerId: serializer.fromJson<String?>(json['customerId']),
      footerNote: serializer.fromJson<String?>(json['footerNote']),
      itemsJson: serializer.fromJson<String>(json['itemsJson']),
      paymentsJson: serializer.fromJson<String>(json['paymentsJson']),
      commandId: serializer.fromJson<String?>(json['commandId']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
      backendReceiptId: serializer.fromJson<String?>(json['backendReceiptId']),
      backendSaleId: serializer.fromJson<String?>(json['backendSaleId']),
      lastSyncError: serializer.fromJson<String?>(json['lastSyncError']),
      lastSyncedAt: serializer.fromJson<int?>(json['lastSyncedAt']),
      tombstone: serializer.fromJson<bool>(json['tombstone']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'total': serializer.toJson<double>(total),
      'discount': serializer.toJson<double>(discount),
      'discountType': serializer.toJson<String>(discountType),
      'paymentMode': serializer.toJson<String>(paymentMode),
      'date': serializer.toJson<String>(date),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'customerName': serializer.toJson<String?>(customerName),
      'customerPhone': serializer.toJson<String?>(customerPhone),
      'customerId': serializer.toJson<String?>(customerId),
      'footerNote': serializer.toJson<String?>(footerNote),
      'itemsJson': serializer.toJson<String>(itemsJson),
      'paymentsJson': serializer.toJson<String>(paymentsJson),
      'commandId': serializer.toJson<String?>(commandId),
      'syncStatus': serializer.toJson<String>(syncStatus),
      'backendReceiptId': serializer.toJson<String?>(backendReceiptId),
      'backendSaleId': serializer.toJson<String?>(backendSaleId),
      'lastSyncError': serializer.toJson<String?>(lastSyncError),
      'lastSyncedAt': serializer.toJson<int?>(lastSyncedAt),
      'tombstone': serializer.toJson<bool>(tombstone),
    };
  }

  SalesEntry copyWith({
    String? id,
    double? total,
    double? discount,
    String? discountType,
    String? paymentMode,
    String? date,
    int? createdAt,
    int? updatedAt,
    Value<String?> customerName = const Value.absent(),
    Value<String?> customerPhone = const Value.absent(),
    Value<String?> customerId = const Value.absent(),
    Value<String?> footerNote = const Value.absent(),
    String? itemsJson,
    String? paymentsJson,
    Value<String?> commandId = const Value.absent(),
    String? syncStatus,
    Value<String?> backendReceiptId = const Value.absent(),
    Value<String?> backendSaleId = const Value.absent(),
    Value<String?> lastSyncError = const Value.absent(),
    Value<int?> lastSyncedAt = const Value.absent(),
    bool? tombstone,
  }) => SalesEntry(
    id: id ?? this.id,
    total: total ?? this.total,
    discount: discount ?? this.discount,
    discountType: discountType ?? this.discountType,
    paymentMode: paymentMode ?? this.paymentMode,
    date: date ?? this.date,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    customerName: customerName.present ? customerName.value : this.customerName,
    customerPhone: customerPhone.present
        ? customerPhone.value
        : this.customerPhone,
    customerId: customerId.present ? customerId.value : this.customerId,
    footerNote: footerNote.present ? footerNote.value : this.footerNote,
    itemsJson: itemsJson ?? this.itemsJson,
    paymentsJson: paymentsJson ?? this.paymentsJson,
    commandId: commandId.present ? commandId.value : this.commandId,
    syncStatus: syncStatus ?? this.syncStatus,
    backendReceiptId: backendReceiptId.present
        ? backendReceiptId.value
        : this.backendReceiptId,
    backendSaleId: backendSaleId.present
        ? backendSaleId.value
        : this.backendSaleId,
    lastSyncError: lastSyncError.present
        ? lastSyncError.value
        : this.lastSyncError,
    lastSyncedAt: lastSyncedAt.present ? lastSyncedAt.value : this.lastSyncedAt,
    tombstone: tombstone ?? this.tombstone,
  );
  SalesEntry copyWithCompanion(SalesEntriesCompanion data) {
    return SalesEntry(
      id: data.id.present ? data.id.value : this.id,
      total: data.total.present ? data.total.value : this.total,
      discount: data.discount.present ? data.discount.value : this.discount,
      discountType: data.discountType.present
          ? data.discountType.value
          : this.discountType,
      paymentMode: data.paymentMode.present
          ? data.paymentMode.value
          : this.paymentMode,
      date: data.date.present ? data.date.value : this.date,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      customerName: data.customerName.present
          ? data.customerName.value
          : this.customerName,
      customerPhone: data.customerPhone.present
          ? data.customerPhone.value
          : this.customerPhone,
      customerId: data.customerId.present
          ? data.customerId.value
          : this.customerId,
      footerNote: data.footerNote.present
          ? data.footerNote.value
          : this.footerNote,
      itemsJson: data.itemsJson.present ? data.itemsJson.value : this.itemsJson,
      paymentsJson: data.paymentsJson.present
          ? data.paymentsJson.value
          : this.paymentsJson,
      commandId: data.commandId.present ? data.commandId.value : this.commandId,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      backendReceiptId: data.backendReceiptId.present
          ? data.backendReceiptId.value
          : this.backendReceiptId,
      backendSaleId: data.backendSaleId.present
          ? data.backendSaleId.value
          : this.backendSaleId,
      lastSyncError: data.lastSyncError.present
          ? data.lastSyncError.value
          : this.lastSyncError,
      lastSyncedAt: data.lastSyncedAt.present
          ? data.lastSyncedAt.value
          : this.lastSyncedAt,
      tombstone: data.tombstone.present ? data.tombstone.value : this.tombstone,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SalesEntry(')
          ..write('id: $id, ')
          ..write('total: $total, ')
          ..write('discount: $discount, ')
          ..write('discountType: $discountType, ')
          ..write('paymentMode: $paymentMode, ')
          ..write('date: $date, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('customerName: $customerName, ')
          ..write('customerPhone: $customerPhone, ')
          ..write('customerId: $customerId, ')
          ..write('footerNote: $footerNote, ')
          ..write('itemsJson: $itemsJson, ')
          ..write('paymentsJson: $paymentsJson, ')
          ..write('commandId: $commandId, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('backendReceiptId: $backendReceiptId, ')
          ..write('backendSaleId: $backendSaleId, ')
          ..write('lastSyncError: $lastSyncError, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('tombstone: $tombstone')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    total,
    discount,
    discountType,
    paymentMode,
    date,
    createdAt,
    updatedAt,
    customerName,
    customerPhone,
    customerId,
    footerNote,
    itemsJson,
    paymentsJson,
    commandId,
    syncStatus,
    backendReceiptId,
    backendSaleId,
    lastSyncError,
    lastSyncedAt,
    tombstone,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SalesEntry &&
          other.id == this.id &&
          other.total == this.total &&
          other.discount == this.discount &&
          other.discountType == this.discountType &&
          other.paymentMode == this.paymentMode &&
          other.date == this.date &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.customerName == this.customerName &&
          other.customerPhone == this.customerPhone &&
          other.customerId == this.customerId &&
          other.footerNote == this.footerNote &&
          other.itemsJson == this.itemsJson &&
          other.paymentsJson == this.paymentsJson &&
          other.commandId == this.commandId &&
          other.syncStatus == this.syncStatus &&
          other.backendReceiptId == this.backendReceiptId &&
          other.backendSaleId == this.backendSaleId &&
          other.lastSyncError == this.lastSyncError &&
          other.lastSyncedAt == this.lastSyncedAt &&
          other.tombstone == this.tombstone);
}

class SalesEntriesCompanion extends UpdateCompanion<SalesEntry> {
  final Value<String> id;
  final Value<double> total;
  final Value<double> discount;
  final Value<String> discountType;
  final Value<String> paymentMode;
  final Value<String> date;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<String?> customerName;
  final Value<String?> customerPhone;
  final Value<String?> customerId;
  final Value<String?> footerNote;
  final Value<String> itemsJson;
  final Value<String> paymentsJson;
  final Value<String?> commandId;
  final Value<String> syncStatus;
  final Value<String?> backendReceiptId;
  final Value<String?> backendSaleId;
  final Value<String?> lastSyncError;
  final Value<int?> lastSyncedAt;
  final Value<bool> tombstone;
  final Value<int> rowid;
  const SalesEntriesCompanion({
    this.id = const Value.absent(),
    this.total = const Value.absent(),
    this.discount = const Value.absent(),
    this.discountType = const Value.absent(),
    this.paymentMode = const Value.absent(),
    this.date = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.customerName = const Value.absent(),
    this.customerPhone = const Value.absent(),
    this.customerId = const Value.absent(),
    this.footerNote = const Value.absent(),
    this.itemsJson = const Value.absent(),
    this.paymentsJson = const Value.absent(),
    this.commandId = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.backendReceiptId = const Value.absent(),
    this.backendSaleId = const Value.absent(),
    this.lastSyncError = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.tombstone = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SalesEntriesCompanion.insert({
    required String id,
    required double total,
    this.discount = const Value.absent(),
    this.discountType = const Value.absent(),
    this.paymentMode = const Value.absent(),
    required String date,
    required int createdAt,
    this.updatedAt = const Value.absent(),
    this.customerName = const Value.absent(),
    this.customerPhone = const Value.absent(),
    this.customerId = const Value.absent(),
    this.footerNote = const Value.absent(),
    required String itemsJson,
    required String paymentsJson,
    this.commandId = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.backendReceiptId = const Value.absent(),
    this.backendSaleId = const Value.absent(),
    this.lastSyncError = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.tombstone = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       total = Value(total),
       date = Value(date),
       createdAt = Value(createdAt),
       itemsJson = Value(itemsJson),
       paymentsJson = Value(paymentsJson);
  static Insertable<SalesEntry> custom({
    Expression<String>? id,
    Expression<double>? total,
    Expression<double>? discount,
    Expression<String>? discountType,
    Expression<String>? paymentMode,
    Expression<String>? date,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<String>? customerName,
    Expression<String>? customerPhone,
    Expression<String>? customerId,
    Expression<String>? footerNote,
    Expression<String>? itemsJson,
    Expression<String>? paymentsJson,
    Expression<String>? commandId,
    Expression<String>? syncStatus,
    Expression<String>? backendReceiptId,
    Expression<String>? backendSaleId,
    Expression<String>? lastSyncError,
    Expression<int>? lastSyncedAt,
    Expression<bool>? tombstone,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (total != null) 'total': total,
      if (discount != null) 'discount': discount,
      if (discountType != null) 'discount_type': discountType,
      if (paymentMode != null) 'payment_mode': paymentMode,
      if (date != null) 'date': date,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (customerName != null) 'customer_name': customerName,
      if (customerPhone != null) 'customer_phone': customerPhone,
      if (customerId != null) 'customer_id': customerId,
      if (footerNote != null) 'footer_note': footerNote,
      if (itemsJson != null) 'items_json': itemsJson,
      if (paymentsJson != null) 'payments_json': paymentsJson,
      if (commandId != null) 'command_id': commandId,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (backendReceiptId != null) 'backend_receipt_id': backendReceiptId,
      if (backendSaleId != null) 'backend_sale_id': backendSaleId,
      if (lastSyncError != null) 'last_sync_error': lastSyncError,
      if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt,
      if (tombstone != null) 'tombstone': tombstone,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SalesEntriesCompanion copyWith({
    Value<String>? id,
    Value<double>? total,
    Value<double>? discount,
    Value<String>? discountType,
    Value<String>? paymentMode,
    Value<String>? date,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<String?>? customerName,
    Value<String?>? customerPhone,
    Value<String?>? customerId,
    Value<String?>? footerNote,
    Value<String>? itemsJson,
    Value<String>? paymentsJson,
    Value<String?>? commandId,
    Value<String>? syncStatus,
    Value<String?>? backendReceiptId,
    Value<String?>? backendSaleId,
    Value<String?>? lastSyncError,
    Value<int?>? lastSyncedAt,
    Value<bool>? tombstone,
    Value<int>? rowid,
  }) {
    return SalesEntriesCompanion(
      id: id ?? this.id,
      total: total ?? this.total,
      discount: discount ?? this.discount,
      discountType: discountType ?? this.discountType,
      paymentMode: paymentMode ?? this.paymentMode,
      date: date ?? this.date,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      customerId: customerId ?? this.customerId,
      footerNote: footerNote ?? this.footerNote,
      itemsJson: itemsJson ?? this.itemsJson,
      paymentsJson: paymentsJson ?? this.paymentsJson,
      commandId: commandId ?? this.commandId,
      syncStatus: syncStatus ?? this.syncStatus,
      backendReceiptId: backendReceiptId ?? this.backendReceiptId,
      backendSaleId: backendSaleId ?? this.backendSaleId,
      lastSyncError: lastSyncError ?? this.lastSyncError,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      tombstone: tombstone ?? this.tombstone,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (total.present) {
      map['total'] = Variable<double>(total.value);
    }
    if (discount.present) {
      map['discount'] = Variable<double>(discount.value);
    }
    if (discountType.present) {
      map['discount_type'] = Variable<String>(discountType.value);
    }
    if (paymentMode.present) {
      map['payment_mode'] = Variable<String>(paymentMode.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (customerName.present) {
      map['customer_name'] = Variable<String>(customerName.value);
    }
    if (customerPhone.present) {
      map['customer_phone'] = Variable<String>(customerPhone.value);
    }
    if (customerId.present) {
      map['customer_id'] = Variable<String>(customerId.value);
    }
    if (footerNote.present) {
      map['footer_note'] = Variable<String>(footerNote.value);
    }
    if (itemsJson.present) {
      map['items_json'] = Variable<String>(itemsJson.value);
    }
    if (paymentsJson.present) {
      map['payments_json'] = Variable<String>(paymentsJson.value);
    }
    if (commandId.present) {
      map['command_id'] = Variable<String>(commandId.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (backendReceiptId.present) {
      map['backend_receipt_id'] = Variable<String>(backendReceiptId.value);
    }
    if (backendSaleId.present) {
      map['backend_sale_id'] = Variable<String>(backendSaleId.value);
    }
    if (lastSyncError.present) {
      map['last_sync_error'] = Variable<String>(lastSyncError.value);
    }
    if (lastSyncedAt.present) {
      map['last_synced_at'] = Variable<int>(lastSyncedAt.value);
    }
    if (tombstone.present) {
      map['tombstone'] = Variable<bool>(tombstone.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SalesEntriesCompanion(')
          ..write('id: $id, ')
          ..write('total: $total, ')
          ..write('discount: $discount, ')
          ..write('discountType: $discountType, ')
          ..write('paymentMode: $paymentMode, ')
          ..write('date: $date, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('customerName: $customerName, ')
          ..write('customerPhone: $customerPhone, ')
          ..write('customerId: $customerId, ')
          ..write('footerNote: $footerNote, ')
          ..write('itemsJson: $itemsJson, ')
          ..write('paymentsJson: $paymentsJson, ')
          ..write('commandId: $commandId, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('backendReceiptId: $backendReceiptId, ')
          ..write('backendSaleId: $backendSaleId, ')
          ..write('lastSyncError: $lastSyncError, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('tombstone: $tombstone, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CustomerEntriesTable extends CustomerEntries
    with TableInfo<$CustomerEntriesTable, CustomerEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CustomerEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
    'phone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
    'email',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('active'),
  );
  static const VerificationMeta _totalSpentMeta = const VerificationMeta(
    'totalSpent',
  );
  @override
  late final GeneratedColumn<double> totalSpent = GeneratedColumn<double>(
    'total_spent',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _balanceMeta = const VerificationMeta(
    'balance',
  );
  @override
  late final GeneratedColumn<double> balance = GeneratedColumn<double>(
    'balance',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastSeenAtMeta = const VerificationMeta(
    'lastSeenAt',
  );
  @override
  late final GeneratedColumn<int> lastSeenAt = GeneratedColumn<int>(
    'last_seen_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastRemindedAtMeta = const VerificationMeta(
    'lastRemindedAt',
  );
  @override
  late final GeneratedColumn<int> lastRemindedAt = GeneratedColumn<int>(
    'last_reminded_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tombstoneMeta = const VerificationMeta(
    'tombstone',
  );
  @override
  late final GeneratedColumn<bool> tombstone = GeneratedColumn<bool>(
    'tombstone',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("tombstone" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    phone,
    email,
    notes,
    status,
    totalSpent,
    balance,
    createdAt,
    updatedAt,
    lastSeenAt,
    lastRemindedAt,
    tombstone,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'customers';
  @override
  VerificationContext validateIntegrity(
    Insertable<CustomerEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('phone')) {
      context.handle(
        _phoneMeta,
        phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta),
      );
    }
    if (data.containsKey('email')) {
      context.handle(
        _emailMeta,
        email.isAcceptableOrUnknown(data['email']!, _emailMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('total_spent')) {
      context.handle(
        _totalSpentMeta,
        totalSpent.isAcceptableOrUnknown(data['total_spent']!, _totalSpentMeta),
      );
    }
    if (data.containsKey('balance')) {
      context.handle(
        _balanceMeta,
        balance.isAcceptableOrUnknown(data['balance']!, _balanceMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('last_seen_at')) {
      context.handle(
        _lastSeenAtMeta,
        lastSeenAt.isAcceptableOrUnknown(
          data['last_seen_at']!,
          _lastSeenAtMeta,
        ),
      );
    }
    if (data.containsKey('last_reminded_at')) {
      context.handle(
        _lastRemindedAtMeta,
        lastRemindedAt.isAcceptableOrUnknown(
          data['last_reminded_at']!,
          _lastRemindedAtMeta,
        ),
      );
    }
    if (data.containsKey('tombstone')) {
      context.handle(
        _tombstoneMeta,
        tombstone.isAcceptableOrUnknown(data['tombstone']!, _tombstoneMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CustomerEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CustomerEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      phone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone'],
      ),
      email: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}email'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      totalSpent: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}total_spent'],
      )!,
      balance: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}balance'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      lastSeenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_seen_at'],
      ),
      lastRemindedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_reminded_at'],
      ),
      tombstone: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}tombstone'],
      )!,
    );
  }

  @override
  $CustomerEntriesTable createAlias(String alias) {
    return $CustomerEntriesTable(attachedDatabase, alias);
  }
}

class CustomerEntry extends DataClass implements Insertable<CustomerEntry> {
  final String id;
  final String name;
  final String? phone;
  final String? email;
  final String? notes;
  final String status;
  final double totalSpent;
  final double balance;
  final int createdAt;
  final int updatedAt;
  final int? lastSeenAt;

  /// When a khata reminder was last sent to this customer, so the collection
  /// list can skip anyone already chased today and show who is overdue.
  final int? lastRemindedAt;
  final bool tombstone;
  const CustomerEntry({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.notes,
    required this.status,
    required this.totalSpent,
    required this.balance,
    required this.createdAt,
    required this.updatedAt,
    this.lastSeenAt,
    this.lastRemindedAt,
    required this.tombstone,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || phone != null) {
      map['phone'] = Variable<String>(phone);
    }
    if (!nullToAbsent || email != null) {
      map['email'] = Variable<String>(email);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['status'] = Variable<String>(status);
    map['total_spent'] = Variable<double>(totalSpent);
    map['balance'] = Variable<double>(balance);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || lastSeenAt != null) {
      map['last_seen_at'] = Variable<int>(lastSeenAt);
    }
    if (!nullToAbsent || lastRemindedAt != null) {
      map['last_reminded_at'] = Variable<int>(lastRemindedAt);
    }
    map['tombstone'] = Variable<bool>(tombstone);
    return map;
  }

  CustomerEntriesCompanion toCompanion(bool nullToAbsent) {
    return CustomerEntriesCompanion(
      id: Value(id),
      name: Value(name),
      phone: phone == null && nullToAbsent
          ? const Value.absent()
          : Value(phone),
      email: email == null && nullToAbsent
          ? const Value.absent()
          : Value(email),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      status: Value(status),
      totalSpent: Value(totalSpent),
      balance: Value(balance),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      lastSeenAt: lastSeenAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSeenAt),
      lastRemindedAt: lastRemindedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastRemindedAt),
      tombstone: Value(tombstone),
    );
  }

  factory CustomerEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CustomerEntry(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      phone: serializer.fromJson<String?>(json['phone']),
      email: serializer.fromJson<String?>(json['email']),
      notes: serializer.fromJson<String?>(json['notes']),
      status: serializer.fromJson<String>(json['status']),
      totalSpent: serializer.fromJson<double>(json['totalSpent']),
      balance: serializer.fromJson<double>(json['balance']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      lastSeenAt: serializer.fromJson<int?>(json['lastSeenAt']),
      lastRemindedAt: serializer.fromJson<int?>(json['lastRemindedAt']),
      tombstone: serializer.fromJson<bool>(json['tombstone']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'phone': serializer.toJson<String?>(phone),
      'email': serializer.toJson<String?>(email),
      'notes': serializer.toJson<String?>(notes),
      'status': serializer.toJson<String>(status),
      'totalSpent': serializer.toJson<double>(totalSpent),
      'balance': serializer.toJson<double>(balance),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'lastSeenAt': serializer.toJson<int?>(lastSeenAt),
      'lastRemindedAt': serializer.toJson<int?>(lastRemindedAt),
      'tombstone': serializer.toJson<bool>(tombstone),
    };
  }

  CustomerEntry copyWith({
    String? id,
    String? name,
    Value<String?> phone = const Value.absent(),
    Value<String?> email = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    String? status,
    double? totalSpent,
    double? balance,
    int? createdAt,
    int? updatedAt,
    Value<int?> lastSeenAt = const Value.absent(),
    Value<int?> lastRemindedAt = const Value.absent(),
    bool? tombstone,
  }) => CustomerEntry(
    id: id ?? this.id,
    name: name ?? this.name,
    phone: phone.present ? phone.value : this.phone,
    email: email.present ? email.value : this.email,
    notes: notes.present ? notes.value : this.notes,
    status: status ?? this.status,
    totalSpent: totalSpent ?? this.totalSpent,
    balance: balance ?? this.balance,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    lastSeenAt: lastSeenAt.present ? lastSeenAt.value : this.lastSeenAt,
    lastRemindedAt: lastRemindedAt.present
        ? lastRemindedAt.value
        : this.lastRemindedAt,
    tombstone: tombstone ?? this.tombstone,
  );
  CustomerEntry copyWithCompanion(CustomerEntriesCompanion data) {
    return CustomerEntry(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      phone: data.phone.present ? data.phone.value : this.phone,
      email: data.email.present ? data.email.value : this.email,
      notes: data.notes.present ? data.notes.value : this.notes,
      status: data.status.present ? data.status.value : this.status,
      totalSpent: data.totalSpent.present
          ? data.totalSpent.value
          : this.totalSpent,
      balance: data.balance.present ? data.balance.value : this.balance,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      lastSeenAt: data.lastSeenAt.present
          ? data.lastSeenAt.value
          : this.lastSeenAt,
      lastRemindedAt: data.lastRemindedAt.present
          ? data.lastRemindedAt.value
          : this.lastRemindedAt,
      tombstone: data.tombstone.present ? data.tombstone.value : this.tombstone,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CustomerEntry(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('email: $email, ')
          ..write('notes: $notes, ')
          ..write('status: $status, ')
          ..write('totalSpent: $totalSpent, ')
          ..write('balance: $balance, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('lastRemindedAt: $lastRemindedAt, ')
          ..write('tombstone: $tombstone')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    phone,
    email,
    notes,
    status,
    totalSpent,
    balance,
    createdAt,
    updatedAt,
    lastSeenAt,
    lastRemindedAt,
    tombstone,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CustomerEntry &&
          other.id == this.id &&
          other.name == this.name &&
          other.phone == this.phone &&
          other.email == this.email &&
          other.notes == this.notes &&
          other.status == this.status &&
          other.totalSpent == this.totalSpent &&
          other.balance == this.balance &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.lastSeenAt == this.lastSeenAt &&
          other.lastRemindedAt == this.lastRemindedAt &&
          other.tombstone == this.tombstone);
}

class CustomerEntriesCompanion extends UpdateCompanion<CustomerEntry> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> phone;
  final Value<String?> email;
  final Value<String?> notes;
  final Value<String> status;
  final Value<double> totalSpent;
  final Value<double> balance;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> lastSeenAt;
  final Value<int?> lastRemindedAt;
  final Value<bool> tombstone;
  final Value<int> rowid;
  const CustomerEntriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.phone = const Value.absent(),
    this.email = const Value.absent(),
    this.notes = const Value.absent(),
    this.status = const Value.absent(),
    this.totalSpent = const Value.absent(),
    this.balance = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.lastRemindedAt = const Value.absent(),
    this.tombstone = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CustomerEntriesCompanion.insert({
    required String id,
    required String name,
    this.phone = const Value.absent(),
    this.email = const Value.absent(),
    this.notes = const Value.absent(),
    this.status = const Value.absent(),
    this.totalSpent = const Value.absent(),
    this.balance = const Value.absent(),
    required int createdAt,
    this.updatedAt = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.lastRemindedAt = const Value.absent(),
    this.tombstone = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt);
  static Insertable<CustomerEntry> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? phone,
    Expression<String>? email,
    Expression<String>? notes,
    Expression<String>? status,
    Expression<double>? totalSpent,
    Expression<double>? balance,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? lastSeenAt,
    Expression<int>? lastRemindedAt,
    Expression<bool>? tombstone,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
      if (notes != null) 'notes': notes,
      if (status != null) 'status': status,
      if (totalSpent != null) 'total_spent': totalSpent,
      if (balance != null) 'balance': balance,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (lastSeenAt != null) 'last_seen_at': lastSeenAt,
      if (lastRemindedAt != null) 'last_reminded_at': lastRemindedAt,
      if (tombstone != null) 'tombstone': tombstone,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CustomerEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? phone,
    Value<String?>? email,
    Value<String?>? notes,
    Value<String>? status,
    Value<double>? totalSpent,
    Value<double>? balance,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? lastSeenAt,
    Value<int?>? lastRemindedAt,
    Value<bool>? tombstone,
    Value<int>? rowid,
  }) {
    return CustomerEntriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      totalSpent: totalSpent ?? this.totalSpent,
      balance: balance ?? this.balance,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      lastRemindedAt: lastRemindedAt ?? this.lastRemindedAt,
      tombstone: tombstone ?? this.tombstone,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (totalSpent.present) {
      map['total_spent'] = Variable<double>(totalSpent.value);
    }
    if (balance.present) {
      map['balance'] = Variable<double>(balance.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (lastSeenAt.present) {
      map['last_seen_at'] = Variable<int>(lastSeenAt.value);
    }
    if (lastRemindedAt.present) {
      map['last_reminded_at'] = Variable<int>(lastRemindedAt.value);
    }
    if (tombstone.present) {
      map['tombstone'] = Variable<bool>(tombstone.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CustomerEntriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('email: $email, ')
          ..write('notes: $notes, ')
          ..write('status: $status, ')
          ..write('totalSpent: $totalSpent, ')
          ..write('balance: $balance, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('lastRemindedAt: $lastRemindedAt, ')
          ..write('tombstone: $tombstone, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CommerceOutboxEntriesTable extends CommerceOutboxEntries
    with TableInfo<$CommerceOutboxEntriesTable, CommerceOutboxEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CommerceOutboxEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _commandIdMeta = const VerificationMeta(
    'commandId',
  );
  @override
  late final GeneratedColumn<String> commandId = GeneratedColumn<String>(
    'command_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _shopIdMeta = const VerificationMeta('shopId');
  @override
  late final GeneratedColumn<String> shopId = GeneratedColumn<String>(
    'shop_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _commandTypeMeta = const VerificationMeta(
    'commandType',
  );
  @override
  late final GeneratedColumn<String> commandType = GeneratedColumn<String>(
    'command_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _domainMeta = const VerificationMeta('domain');
  @override
  late final GeneratedColumn<String> domain = GeneratedColumn<String>(
    'domain',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseDomainEpochMeta = const VerificationMeta(
    'baseDomainEpoch',
  );
  @override
  late final GeneratedColumn<int> baseDomainEpoch = GeneratedColumn<int>(
    'base_domain_epoch',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastAttemptAtMeta = const VerificationMeta(
    'lastAttemptAt',
  );
  @override
  late final GeneratedColumn<int> lastAttemptAt = GeneratedColumn<int>(
    'last_attempt_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<int> completedAt = GeneratedColumn<int>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isDeadLetterMeta = const VerificationMeta(
    'isDeadLetter',
  );
  @override
  late final GeneratedColumn<bool> isDeadLetter = GeneratedColumn<bool>(
    'is_dead_letter',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_dead_letter" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _deadLetterReasonMeta = const VerificationMeta(
    'deadLetterReason',
  );
  @override
  late final GeneratedColumn<String> deadLetterReason = GeneratedColumn<String>(
    'dead_letter_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    commandId,
    shopId,
    commandType,
    domain,
    baseDomainEpoch,
    payloadJson,
    syncStatus,
    attemptCount,
    lastError,
    createdAt,
    updatedAt,
    lastAttemptAt,
    completedAt,
    isDeadLetter,
    deadLetterReason,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'commerce_outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<CommerceOutboxEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('command_id')) {
      context.handle(
        _commandIdMeta,
        commandId.isAcceptableOrUnknown(data['command_id']!, _commandIdMeta),
      );
    } else if (isInserting) {
      context.missing(_commandIdMeta);
    }
    if (data.containsKey('shop_id')) {
      context.handle(
        _shopIdMeta,
        shopId.isAcceptableOrUnknown(data['shop_id']!, _shopIdMeta),
      );
    } else if (isInserting) {
      context.missing(_shopIdMeta);
    }
    if (data.containsKey('command_type')) {
      context.handle(
        _commandTypeMeta,
        commandType.isAcceptableOrUnknown(
          data['command_type']!,
          _commandTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_commandTypeMeta);
    }
    if (data.containsKey('domain')) {
      context.handle(
        _domainMeta,
        domain.isAcceptableOrUnknown(data['domain']!, _domainMeta),
      );
    } else if (isInserting) {
      context.missing(_domainMeta);
    }
    if (data.containsKey('base_domain_epoch')) {
      context.handle(
        _baseDomainEpochMeta,
        baseDomainEpoch.isAcceptableOrUnknown(
          data['base_domain_epoch']!,
          _baseDomainEpochMeta,
        ),
      );
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('last_attempt_at')) {
      context.handle(
        _lastAttemptAtMeta,
        lastAttemptAt.isAcceptableOrUnknown(
          data['last_attempt_at']!,
          _lastAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    if (data.containsKey('is_dead_letter')) {
      context.handle(
        _isDeadLetterMeta,
        isDeadLetter.isAcceptableOrUnknown(
          data['is_dead_letter']!,
          _isDeadLetterMeta,
        ),
      );
    }
    if (data.containsKey('dead_letter_reason')) {
      context.handle(
        _deadLetterReasonMeta,
        deadLetterReason.isAcceptableOrUnknown(
          data['dead_letter_reason']!,
          _deadLetterReasonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {commandId};
  @override
  CommerceOutboxEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CommerceOutboxEntry(
      commandId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}command_id'],
      )!,
      shopId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shop_id'],
      )!,
      commandType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}command_type'],
      )!,
      domain: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}domain'],
      )!,
      baseDomainEpoch: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}base_domain_epoch'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_status'],
      )!,
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      lastAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_attempt_at'],
      ),
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completed_at'],
      ),
      isDeadLetter: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_dead_letter'],
      )!,
      deadLetterReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dead_letter_reason'],
      ),
    );
  }

  @override
  $CommerceOutboxEntriesTable createAlias(String alias) {
    return $CommerceOutboxEntriesTable(attachedDatabase, alias);
  }
}

class CommerceOutboxEntry extends DataClass
    implements Insertable<CommerceOutboxEntry> {
  final String commandId;
  final String shopId;
  final String commandType;
  final String domain;
  final int baseDomainEpoch;
  final String payloadJson;
  final String syncStatus;
  final int attemptCount;
  final String? lastError;
  final int createdAt;
  final int updatedAt;
  final int? lastAttemptAt;
  final int? completedAt;
  final bool isDeadLetter;
  final String? deadLetterReason;
  const CommerceOutboxEntry({
    required this.commandId,
    required this.shopId,
    required this.commandType,
    required this.domain,
    required this.baseDomainEpoch,
    required this.payloadJson,
    required this.syncStatus,
    required this.attemptCount,
    this.lastError,
    required this.createdAt,
    required this.updatedAt,
    this.lastAttemptAt,
    this.completedAt,
    required this.isDeadLetter,
    this.deadLetterReason,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['command_id'] = Variable<String>(commandId);
    map['shop_id'] = Variable<String>(shopId);
    map['command_type'] = Variable<String>(commandType);
    map['domain'] = Variable<String>(domain);
    map['base_domain_epoch'] = Variable<int>(baseDomainEpoch);
    map['payload_json'] = Variable<String>(payloadJson);
    map['sync_status'] = Variable<String>(syncStatus);
    map['attempt_count'] = Variable<int>(attemptCount);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || lastAttemptAt != null) {
      map['last_attempt_at'] = Variable<int>(lastAttemptAt);
    }
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<int>(completedAt);
    }
    map['is_dead_letter'] = Variable<bool>(isDeadLetter);
    if (!nullToAbsent || deadLetterReason != null) {
      map['dead_letter_reason'] = Variable<String>(deadLetterReason);
    }
    return map;
  }

  CommerceOutboxEntriesCompanion toCompanion(bool nullToAbsent) {
    return CommerceOutboxEntriesCompanion(
      commandId: Value(commandId),
      shopId: Value(shopId),
      commandType: Value(commandType),
      domain: Value(domain),
      baseDomainEpoch: Value(baseDomainEpoch),
      payloadJson: Value(payloadJson),
      syncStatus: Value(syncStatus),
      attemptCount: Value(attemptCount),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      lastAttemptAt: lastAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAttemptAt),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      isDeadLetter: Value(isDeadLetter),
      deadLetterReason: deadLetterReason == null && nullToAbsent
          ? const Value.absent()
          : Value(deadLetterReason),
    );
  }

  factory CommerceOutboxEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CommerceOutboxEntry(
      commandId: serializer.fromJson<String>(json['commandId']),
      shopId: serializer.fromJson<String>(json['shopId']),
      commandType: serializer.fromJson<String>(json['commandType']),
      domain: serializer.fromJson<String>(json['domain']),
      baseDomainEpoch: serializer.fromJson<int>(json['baseDomainEpoch']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      lastAttemptAt: serializer.fromJson<int?>(json['lastAttemptAt']),
      completedAt: serializer.fromJson<int?>(json['completedAt']),
      isDeadLetter: serializer.fromJson<bool>(json['isDeadLetter']),
      deadLetterReason: serializer.fromJson<String?>(json['deadLetterReason']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'commandId': serializer.toJson<String>(commandId),
      'shopId': serializer.toJson<String>(shopId),
      'commandType': serializer.toJson<String>(commandType),
      'domain': serializer.toJson<String>(domain),
      'baseDomainEpoch': serializer.toJson<int>(baseDomainEpoch),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'syncStatus': serializer.toJson<String>(syncStatus),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'lastError': serializer.toJson<String?>(lastError),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'lastAttemptAt': serializer.toJson<int?>(lastAttemptAt),
      'completedAt': serializer.toJson<int?>(completedAt),
      'isDeadLetter': serializer.toJson<bool>(isDeadLetter),
      'deadLetterReason': serializer.toJson<String?>(deadLetterReason),
    };
  }

  CommerceOutboxEntry copyWith({
    String? commandId,
    String? shopId,
    String? commandType,
    String? domain,
    int? baseDomainEpoch,
    String? payloadJson,
    String? syncStatus,
    int? attemptCount,
    Value<String?> lastError = const Value.absent(),
    int? createdAt,
    int? updatedAt,
    Value<int?> lastAttemptAt = const Value.absent(),
    Value<int?> completedAt = const Value.absent(),
    bool? isDeadLetter,
    Value<String?> deadLetterReason = const Value.absent(),
  }) => CommerceOutboxEntry(
    commandId: commandId ?? this.commandId,
    shopId: shopId ?? this.shopId,
    commandType: commandType ?? this.commandType,
    domain: domain ?? this.domain,
    baseDomainEpoch: baseDomainEpoch ?? this.baseDomainEpoch,
    payloadJson: payloadJson ?? this.payloadJson,
    syncStatus: syncStatus ?? this.syncStatus,
    attemptCount: attemptCount ?? this.attemptCount,
    lastError: lastError.present ? lastError.value : this.lastError,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    lastAttemptAt: lastAttemptAt.present
        ? lastAttemptAt.value
        : this.lastAttemptAt,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
    isDeadLetter: isDeadLetter ?? this.isDeadLetter,
    deadLetterReason: deadLetterReason.present
        ? deadLetterReason.value
        : this.deadLetterReason,
  );
  CommerceOutboxEntry copyWithCompanion(CommerceOutboxEntriesCompanion data) {
    return CommerceOutboxEntry(
      commandId: data.commandId.present ? data.commandId.value : this.commandId,
      shopId: data.shopId.present ? data.shopId.value : this.shopId,
      commandType: data.commandType.present
          ? data.commandType.value
          : this.commandType,
      domain: data.domain.present ? data.domain.value : this.domain,
      baseDomainEpoch: data.baseDomainEpoch.present
          ? data.baseDomainEpoch.value
          : this.baseDomainEpoch,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      lastAttemptAt: data.lastAttemptAt.present
          ? data.lastAttemptAt.value
          : this.lastAttemptAt,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      isDeadLetter: data.isDeadLetter.present
          ? data.isDeadLetter.value
          : this.isDeadLetter,
      deadLetterReason: data.deadLetterReason.present
          ? data.deadLetterReason.value
          : this.deadLetterReason,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CommerceOutboxEntry(')
          ..write('commandId: $commandId, ')
          ..write('shopId: $shopId, ')
          ..write('commandType: $commandType, ')
          ..write('domain: $domain, ')
          ..write('baseDomainEpoch: $baseDomainEpoch, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('isDeadLetter: $isDeadLetter, ')
          ..write('deadLetterReason: $deadLetterReason')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    commandId,
    shopId,
    commandType,
    domain,
    baseDomainEpoch,
    payloadJson,
    syncStatus,
    attemptCount,
    lastError,
    createdAt,
    updatedAt,
    lastAttemptAt,
    completedAt,
    isDeadLetter,
    deadLetterReason,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CommerceOutboxEntry &&
          other.commandId == this.commandId &&
          other.shopId == this.shopId &&
          other.commandType == this.commandType &&
          other.domain == this.domain &&
          other.baseDomainEpoch == this.baseDomainEpoch &&
          other.payloadJson == this.payloadJson &&
          other.syncStatus == this.syncStatus &&
          other.attemptCount == this.attemptCount &&
          other.lastError == this.lastError &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.lastAttemptAt == this.lastAttemptAt &&
          other.completedAt == this.completedAt &&
          other.isDeadLetter == this.isDeadLetter &&
          other.deadLetterReason == this.deadLetterReason);
}

class CommerceOutboxEntriesCompanion
    extends UpdateCompanion<CommerceOutboxEntry> {
  final Value<String> commandId;
  final Value<String> shopId;
  final Value<String> commandType;
  final Value<String> domain;
  final Value<int> baseDomainEpoch;
  final Value<String> payloadJson;
  final Value<String> syncStatus;
  final Value<int> attemptCount;
  final Value<String?> lastError;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> lastAttemptAt;
  final Value<int?> completedAt;
  final Value<bool> isDeadLetter;
  final Value<String?> deadLetterReason;
  final Value<int> rowid;
  const CommerceOutboxEntriesCompanion({
    this.commandId = const Value.absent(),
    this.shopId = const Value.absent(),
    this.commandType = const Value.absent(),
    this.domain = const Value.absent(),
    this.baseDomainEpoch = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.isDeadLetter = const Value.absent(),
    this.deadLetterReason = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CommerceOutboxEntriesCompanion.insert({
    required String commandId,
    required String shopId,
    required String commandType,
    required String domain,
    this.baseDomainEpoch = const Value.absent(),
    required String payloadJson,
    this.syncStatus = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.lastError = const Value.absent(),
    required int createdAt,
    this.updatedAt = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.isDeadLetter = const Value.absent(),
    this.deadLetterReason = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : commandId = Value(commandId),
       shopId = Value(shopId),
       commandType = Value(commandType),
       domain = Value(domain),
       payloadJson = Value(payloadJson),
       createdAt = Value(createdAt);
  static Insertable<CommerceOutboxEntry> custom({
    Expression<String>? commandId,
    Expression<String>? shopId,
    Expression<String>? commandType,
    Expression<String>? domain,
    Expression<int>? baseDomainEpoch,
    Expression<String>? payloadJson,
    Expression<String>? syncStatus,
    Expression<int>? attemptCount,
    Expression<String>? lastError,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? lastAttemptAt,
    Expression<int>? completedAt,
    Expression<bool>? isDeadLetter,
    Expression<String>? deadLetterReason,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (commandId != null) 'command_id': commandId,
      if (shopId != null) 'shop_id': shopId,
      if (commandType != null) 'command_type': commandType,
      if (domain != null) 'domain': domain,
      if (baseDomainEpoch != null) 'base_domain_epoch': baseDomainEpoch,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (lastError != null) 'last_error': lastError,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (lastAttemptAt != null) 'last_attempt_at': lastAttemptAt,
      if (completedAt != null) 'completed_at': completedAt,
      if (isDeadLetter != null) 'is_dead_letter': isDeadLetter,
      if (deadLetterReason != null) 'dead_letter_reason': deadLetterReason,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CommerceOutboxEntriesCompanion copyWith({
    Value<String>? commandId,
    Value<String>? shopId,
    Value<String>? commandType,
    Value<String>? domain,
    Value<int>? baseDomainEpoch,
    Value<String>? payloadJson,
    Value<String>? syncStatus,
    Value<int>? attemptCount,
    Value<String?>? lastError,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? lastAttemptAt,
    Value<int?>? completedAt,
    Value<bool>? isDeadLetter,
    Value<String?>? deadLetterReason,
    Value<int>? rowid,
  }) {
    return CommerceOutboxEntriesCompanion(
      commandId: commandId ?? this.commandId,
      shopId: shopId ?? this.shopId,
      commandType: commandType ?? this.commandType,
      domain: domain ?? this.domain,
      baseDomainEpoch: baseDomainEpoch ?? this.baseDomainEpoch,
      payloadJson: payloadJson ?? this.payloadJson,
      syncStatus: syncStatus ?? this.syncStatus,
      attemptCount: attemptCount ?? this.attemptCount,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      completedAt: completedAt ?? this.completedAt,
      isDeadLetter: isDeadLetter ?? this.isDeadLetter,
      deadLetterReason: deadLetterReason ?? this.deadLetterReason,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (commandId.present) {
      map['command_id'] = Variable<String>(commandId.value);
    }
    if (shopId.present) {
      map['shop_id'] = Variable<String>(shopId.value);
    }
    if (commandType.present) {
      map['command_type'] = Variable<String>(commandType.value);
    }
    if (domain.present) {
      map['domain'] = Variable<String>(domain.value);
    }
    if (baseDomainEpoch.present) {
      map['base_domain_epoch'] = Variable<int>(baseDomainEpoch.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (lastAttemptAt.present) {
      map['last_attempt_at'] = Variable<int>(lastAttemptAt.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<int>(completedAt.value);
    }
    if (isDeadLetter.present) {
      map['is_dead_letter'] = Variable<bool>(isDeadLetter.value);
    }
    if (deadLetterReason.present) {
      map['dead_letter_reason'] = Variable<String>(deadLetterReason.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CommerceOutboxEntriesCompanion(')
          ..write('commandId: $commandId, ')
          ..write('shopId: $shopId, ')
          ..write('commandType: $commandType, ')
          ..write('domain: $domain, ')
          ..write('baseDomainEpoch: $baseDomainEpoch, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('isDeadLetter: $isDeadLetter, ')
          ..write('deadLetterReason: $deadLetterReason, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ExpenseEntriesTable extends ExpenseEntries
    with TableInfo<$ExpenseEntriesTable, ExpenseEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExpenseEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('General'),
  );
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
    'amount',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _paymentMethodMeta = const VerificationMeta(
    'paymentMethod',
  );
  @override
  late final GeneratedColumn<String> paymentMethod = GeneratedColumn<String>(
    'payment_method',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('CASH'),
  );
  static const VerificationMeta _paymentReferenceMeta = const VerificationMeta(
    'paymentReference',
  );
  @override
  late final GeneratedColumn<String> paymentReference = GeneratedColumn<String>(
    'payment_reference',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _expenseDateMeta = const VerificationMeta(
    'expenseDate',
  );
  @override
  late final GeneratedColumn<String> expenseDate = GeneratedColumn<String>(
    'expense_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actorNameMeta = const VerificationMeta(
    'actorName',
  );
  @override
  late final GeneratedColumn<String> actorName = GeneratedColumn<String>(
    'actor_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _tombstoneMeta = const VerificationMeta(
    'tombstone',
  );
  @override
  late final GeneratedColumn<bool> tombstone = GeneratedColumn<bool>(
    'tombstone',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("tombstone" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    category,
    amount,
    description,
    paymentMethod,
    paymentReference,
    expenseDate,
    actorName,
    createdAt,
    updatedAt,
    tombstone,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'expenses';
  @override
  VerificationContext validateIntegrity(
    Insertable<ExpenseEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('payment_method')) {
      context.handle(
        _paymentMethodMeta,
        paymentMethod.isAcceptableOrUnknown(
          data['payment_method']!,
          _paymentMethodMeta,
        ),
      );
    }
    if (data.containsKey('payment_reference')) {
      context.handle(
        _paymentReferenceMeta,
        paymentReference.isAcceptableOrUnknown(
          data['payment_reference']!,
          _paymentReferenceMeta,
        ),
      );
    }
    if (data.containsKey('expense_date')) {
      context.handle(
        _expenseDateMeta,
        expenseDate.isAcceptableOrUnknown(
          data['expense_date']!,
          _expenseDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_expenseDateMeta);
    }
    if (data.containsKey('actor_name')) {
      context.handle(
        _actorNameMeta,
        actorName.isAcceptableOrUnknown(data['actor_name']!, _actorNameMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('tombstone')) {
      context.handle(
        _tombstoneMeta,
        tombstone.isAcceptableOrUnknown(data['tombstone']!, _tombstoneMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ExpenseEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExpenseEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}amount'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      paymentMethod: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payment_method'],
      )!,
      paymentReference: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payment_reference'],
      )!,
      expenseDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}expense_date'],
      )!,
      actorName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}actor_name'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      tombstone: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}tombstone'],
      )!,
    );
  }

  @override
  $ExpenseEntriesTable createAlias(String alias) {
    return $ExpenseEntriesTable(attachedDatabase, alias);
  }
}

class ExpenseEntry extends DataClass implements Insertable<ExpenseEntry> {
  final String id;
  final String category;
  final double amount;
  final String description;
  final String paymentMethod;
  final String paymentReference;
  final String expenseDate;
  final String? actorName;
  final int createdAt;
  final int updatedAt;
  final bool tombstone;
  const ExpenseEntry({
    required this.id,
    required this.category,
    required this.amount,
    required this.description,
    required this.paymentMethod,
    required this.paymentReference,
    required this.expenseDate,
    this.actorName,
    required this.createdAt,
    required this.updatedAt,
    required this.tombstone,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['category'] = Variable<String>(category);
    map['amount'] = Variable<double>(amount);
    map['description'] = Variable<String>(description);
    map['payment_method'] = Variable<String>(paymentMethod);
    map['payment_reference'] = Variable<String>(paymentReference);
    map['expense_date'] = Variable<String>(expenseDate);
    if (!nullToAbsent || actorName != null) {
      map['actor_name'] = Variable<String>(actorName);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    map['tombstone'] = Variable<bool>(tombstone);
    return map;
  }

  ExpenseEntriesCompanion toCompanion(bool nullToAbsent) {
    return ExpenseEntriesCompanion(
      id: Value(id),
      category: Value(category),
      amount: Value(amount),
      description: Value(description),
      paymentMethod: Value(paymentMethod),
      paymentReference: Value(paymentReference),
      expenseDate: Value(expenseDate),
      actorName: actorName == null && nullToAbsent
          ? const Value.absent()
          : Value(actorName),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      tombstone: Value(tombstone),
    );
  }

  factory ExpenseEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExpenseEntry(
      id: serializer.fromJson<String>(json['id']),
      category: serializer.fromJson<String>(json['category']),
      amount: serializer.fromJson<double>(json['amount']),
      description: serializer.fromJson<String>(json['description']),
      paymentMethod: serializer.fromJson<String>(json['paymentMethod']),
      paymentReference: serializer.fromJson<String>(json['paymentReference']),
      expenseDate: serializer.fromJson<String>(json['expenseDate']),
      actorName: serializer.fromJson<String?>(json['actorName']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      tombstone: serializer.fromJson<bool>(json['tombstone']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'category': serializer.toJson<String>(category),
      'amount': serializer.toJson<double>(amount),
      'description': serializer.toJson<String>(description),
      'paymentMethod': serializer.toJson<String>(paymentMethod),
      'paymentReference': serializer.toJson<String>(paymentReference),
      'expenseDate': serializer.toJson<String>(expenseDate),
      'actorName': serializer.toJson<String?>(actorName),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'tombstone': serializer.toJson<bool>(tombstone),
    };
  }

  ExpenseEntry copyWith({
    String? id,
    String? category,
    double? amount,
    String? description,
    String? paymentMethod,
    String? paymentReference,
    String? expenseDate,
    Value<String?> actorName = const Value.absent(),
    int? createdAt,
    int? updatedAt,
    bool? tombstone,
  }) => ExpenseEntry(
    id: id ?? this.id,
    category: category ?? this.category,
    amount: amount ?? this.amount,
    description: description ?? this.description,
    paymentMethod: paymentMethod ?? this.paymentMethod,
    paymentReference: paymentReference ?? this.paymentReference,
    expenseDate: expenseDate ?? this.expenseDate,
    actorName: actorName.present ? actorName.value : this.actorName,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    tombstone: tombstone ?? this.tombstone,
  );
  ExpenseEntry copyWithCompanion(ExpenseEntriesCompanion data) {
    return ExpenseEntry(
      id: data.id.present ? data.id.value : this.id,
      category: data.category.present ? data.category.value : this.category,
      amount: data.amount.present ? data.amount.value : this.amount,
      description: data.description.present
          ? data.description.value
          : this.description,
      paymentMethod: data.paymentMethod.present
          ? data.paymentMethod.value
          : this.paymentMethod,
      paymentReference: data.paymentReference.present
          ? data.paymentReference.value
          : this.paymentReference,
      expenseDate: data.expenseDate.present
          ? data.expenseDate.value
          : this.expenseDate,
      actorName: data.actorName.present ? data.actorName.value : this.actorName,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      tombstone: data.tombstone.present ? data.tombstone.value : this.tombstone,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExpenseEntry(')
          ..write('id: $id, ')
          ..write('category: $category, ')
          ..write('amount: $amount, ')
          ..write('description: $description, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('paymentReference: $paymentReference, ')
          ..write('expenseDate: $expenseDate, ')
          ..write('actorName: $actorName, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('tombstone: $tombstone')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    category,
    amount,
    description,
    paymentMethod,
    paymentReference,
    expenseDate,
    actorName,
    createdAt,
    updatedAt,
    tombstone,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExpenseEntry &&
          other.id == this.id &&
          other.category == this.category &&
          other.amount == this.amount &&
          other.description == this.description &&
          other.paymentMethod == this.paymentMethod &&
          other.paymentReference == this.paymentReference &&
          other.expenseDate == this.expenseDate &&
          other.actorName == this.actorName &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.tombstone == this.tombstone);
}

class ExpenseEntriesCompanion extends UpdateCompanion<ExpenseEntry> {
  final Value<String> id;
  final Value<String> category;
  final Value<double> amount;
  final Value<String> description;
  final Value<String> paymentMethod;
  final Value<String> paymentReference;
  final Value<String> expenseDate;
  final Value<String?> actorName;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<bool> tombstone;
  final Value<int> rowid;
  const ExpenseEntriesCompanion({
    this.id = const Value.absent(),
    this.category = const Value.absent(),
    this.amount = const Value.absent(),
    this.description = const Value.absent(),
    this.paymentMethod = const Value.absent(),
    this.paymentReference = const Value.absent(),
    this.expenseDate = const Value.absent(),
    this.actorName = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.tombstone = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExpenseEntriesCompanion.insert({
    required String id,
    this.category = const Value.absent(),
    this.amount = const Value.absent(),
    this.description = const Value.absent(),
    this.paymentMethod = const Value.absent(),
    this.paymentReference = const Value.absent(),
    required String expenseDate,
    this.actorName = const Value.absent(),
    required int createdAt,
    this.updatedAt = const Value.absent(),
    this.tombstone = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       expenseDate = Value(expenseDate),
       createdAt = Value(createdAt);
  static Insertable<ExpenseEntry> custom({
    Expression<String>? id,
    Expression<String>? category,
    Expression<double>? amount,
    Expression<String>? description,
    Expression<String>? paymentMethod,
    Expression<String>? paymentReference,
    Expression<String>? expenseDate,
    Expression<String>? actorName,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<bool>? tombstone,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (category != null) 'category': category,
      if (amount != null) 'amount': amount,
      if (description != null) 'description': description,
      if (paymentMethod != null) 'payment_method': paymentMethod,
      if (paymentReference != null) 'payment_reference': paymentReference,
      if (expenseDate != null) 'expense_date': expenseDate,
      if (actorName != null) 'actor_name': actorName,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (tombstone != null) 'tombstone': tombstone,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExpenseEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? category,
    Value<double>? amount,
    Value<String>? description,
    Value<String>? paymentMethod,
    Value<String>? paymentReference,
    Value<String>? expenseDate,
    Value<String?>? actorName,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<bool>? tombstone,
    Value<int>? rowid,
  }) {
    return ExpenseEntriesCompanion(
      id: id ?? this.id,
      category: category ?? this.category,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentReference: paymentReference ?? this.paymentReference,
      expenseDate: expenseDate ?? this.expenseDate,
      actorName: actorName ?? this.actorName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      tombstone: tombstone ?? this.tombstone,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (amount.present) {
      map['amount'] = Variable<double>(amount.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (paymentMethod.present) {
      map['payment_method'] = Variable<String>(paymentMethod.value);
    }
    if (paymentReference.present) {
      map['payment_reference'] = Variable<String>(paymentReference.value);
    }
    if (expenseDate.present) {
      map['expense_date'] = Variable<String>(expenseDate.value);
    }
    if (actorName.present) {
      map['actor_name'] = Variable<String>(actorName.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (tombstone.present) {
      map['tombstone'] = Variable<bool>(tombstone.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExpenseEntriesCompanion(')
          ..write('id: $id, ')
          ..write('category: $category, ')
          ..write('amount: $amount, ')
          ..write('description: $description, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('paymentReference: $paymentReference, ')
          ..write('expenseDate: $expenseDate, ')
          ..write('actorName: $actorName, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('tombstone: $tombstone, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PurchaseEntriesTable extends PurchaseEntries
    with TableInfo<$PurchaseEntriesTable, PurchaseEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PurchaseEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _supplierNameMeta = const VerificationMeta(
    'supplierName',
  );
  @override
  late final GeneratedColumn<String> supplierName = GeneratedColumn<String>(
    'supplier_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _supplierPhoneMeta = const VerificationMeta(
    'supplierPhone',
  );
  @override
  late final GeneratedColumn<String> supplierPhone = GeneratedColumn<String>(
    'supplier_phone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _referenceMeta = const VerificationMeta(
    'reference',
  );
  @override
  late final GeneratedColumn<String> reference = GeneratedColumn<String>(
    'reference',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _totalMeta = const VerificationMeta('total');
  @override
  late final GeneratedColumn<double> total = GeneratedColumn<double>(
    'total',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _amountPaidMeta = const VerificationMeta(
    'amountPaid',
  );
  @override
  late final GeneratedColumn<double> amountPaid = GeneratedColumn<double>(
    'amount_paid',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _paymentMethodMeta = const VerificationMeta(
    'paymentMethod',
  );
  @override
  late final GeneratedColumn<String> paymentMethod = GeneratedColumn<String>(
    'payment_method',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('CASH'),
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _purchaseDateMeta = const VerificationMeta(
    'purchaseDate',
  );
  @override
  late final GeneratedColumn<String> purchaseDate = GeneratedColumn<String>(
    'purchase_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actorNameMeta = const VerificationMeta(
    'actorName',
  );
  @override
  late final GeneratedColumn<String> actorName = GeneratedColumn<String>(
    'actor_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _tombstoneMeta = const VerificationMeta(
    'tombstone',
  );
  @override
  late final GeneratedColumn<bool> tombstone = GeneratedColumn<bool>(
    'tombstone',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("tombstone" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    supplierName,
    supplierPhone,
    reference,
    total,
    amountPaid,
    paymentMethod,
    notes,
    purchaseDate,
    actorName,
    createdAt,
    updatedAt,
    tombstone,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'purchases';
  @override
  VerificationContext validateIntegrity(
    Insertable<PurchaseEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('supplier_name')) {
      context.handle(
        _supplierNameMeta,
        supplierName.isAcceptableOrUnknown(
          data['supplier_name']!,
          _supplierNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_supplierNameMeta);
    }
    if (data.containsKey('supplier_phone')) {
      context.handle(
        _supplierPhoneMeta,
        supplierPhone.isAcceptableOrUnknown(
          data['supplier_phone']!,
          _supplierPhoneMeta,
        ),
      );
    }
    if (data.containsKey('reference')) {
      context.handle(
        _referenceMeta,
        reference.isAcceptableOrUnknown(data['reference']!, _referenceMeta),
      );
    }
    if (data.containsKey('total')) {
      context.handle(
        _totalMeta,
        total.isAcceptableOrUnknown(data['total']!, _totalMeta),
      );
    }
    if (data.containsKey('amount_paid')) {
      context.handle(
        _amountPaidMeta,
        amountPaid.isAcceptableOrUnknown(data['amount_paid']!, _amountPaidMeta),
      );
    }
    if (data.containsKey('payment_method')) {
      context.handle(
        _paymentMethodMeta,
        paymentMethod.isAcceptableOrUnknown(
          data['payment_method']!,
          _paymentMethodMeta,
        ),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('purchase_date')) {
      context.handle(
        _purchaseDateMeta,
        purchaseDate.isAcceptableOrUnknown(
          data['purchase_date']!,
          _purchaseDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_purchaseDateMeta);
    }
    if (data.containsKey('actor_name')) {
      context.handle(
        _actorNameMeta,
        actorName.isAcceptableOrUnknown(data['actor_name']!, _actorNameMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('tombstone')) {
      context.handle(
        _tombstoneMeta,
        tombstone.isAcceptableOrUnknown(data['tombstone']!, _tombstoneMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PurchaseEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PurchaseEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      supplierName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}supplier_name'],
      )!,
      supplierPhone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}supplier_phone'],
      )!,
      reference: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reference'],
      )!,
      total: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}total'],
      )!,
      amountPaid: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}amount_paid'],
      )!,
      paymentMethod: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payment_method'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      )!,
      purchaseDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}purchase_date'],
      )!,
      actorName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}actor_name'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      tombstone: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}tombstone'],
      )!,
    );
  }

  @override
  $PurchaseEntriesTable createAlias(String alias) {
    return $PurchaseEntriesTable(attachedDatabase, alias);
  }
}

class PurchaseEntry extends DataClass implements Insertable<PurchaseEntry> {
  final String id;
  final String supplierName;
  final String supplierPhone;
  final String reference;
  final double total;
  final double amountPaid;
  final String paymentMethod;
  final String notes;
  final String purchaseDate;
  final String? actorName;
  final int createdAt;
  final int updatedAt;
  final bool tombstone;
  const PurchaseEntry({
    required this.id,
    required this.supplierName,
    required this.supplierPhone,
    required this.reference,
    required this.total,
    required this.amountPaid,
    required this.paymentMethod,
    required this.notes,
    required this.purchaseDate,
    this.actorName,
    required this.createdAt,
    required this.updatedAt,
    required this.tombstone,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['supplier_name'] = Variable<String>(supplierName);
    map['supplier_phone'] = Variable<String>(supplierPhone);
    map['reference'] = Variable<String>(reference);
    map['total'] = Variable<double>(total);
    map['amount_paid'] = Variable<double>(amountPaid);
    map['payment_method'] = Variable<String>(paymentMethod);
    map['notes'] = Variable<String>(notes);
    map['purchase_date'] = Variable<String>(purchaseDate);
    if (!nullToAbsent || actorName != null) {
      map['actor_name'] = Variable<String>(actorName);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    map['tombstone'] = Variable<bool>(tombstone);
    return map;
  }

  PurchaseEntriesCompanion toCompanion(bool nullToAbsent) {
    return PurchaseEntriesCompanion(
      id: Value(id),
      supplierName: Value(supplierName),
      supplierPhone: Value(supplierPhone),
      reference: Value(reference),
      total: Value(total),
      amountPaid: Value(amountPaid),
      paymentMethod: Value(paymentMethod),
      notes: Value(notes),
      purchaseDate: Value(purchaseDate),
      actorName: actorName == null && nullToAbsent
          ? const Value.absent()
          : Value(actorName),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      tombstone: Value(tombstone),
    );
  }

  factory PurchaseEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PurchaseEntry(
      id: serializer.fromJson<String>(json['id']),
      supplierName: serializer.fromJson<String>(json['supplierName']),
      supplierPhone: serializer.fromJson<String>(json['supplierPhone']),
      reference: serializer.fromJson<String>(json['reference']),
      total: serializer.fromJson<double>(json['total']),
      amountPaid: serializer.fromJson<double>(json['amountPaid']),
      paymentMethod: serializer.fromJson<String>(json['paymentMethod']),
      notes: serializer.fromJson<String>(json['notes']),
      purchaseDate: serializer.fromJson<String>(json['purchaseDate']),
      actorName: serializer.fromJson<String?>(json['actorName']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      tombstone: serializer.fromJson<bool>(json['tombstone']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'supplierName': serializer.toJson<String>(supplierName),
      'supplierPhone': serializer.toJson<String>(supplierPhone),
      'reference': serializer.toJson<String>(reference),
      'total': serializer.toJson<double>(total),
      'amountPaid': serializer.toJson<double>(amountPaid),
      'paymentMethod': serializer.toJson<String>(paymentMethod),
      'notes': serializer.toJson<String>(notes),
      'purchaseDate': serializer.toJson<String>(purchaseDate),
      'actorName': serializer.toJson<String?>(actorName),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'tombstone': serializer.toJson<bool>(tombstone),
    };
  }

  PurchaseEntry copyWith({
    String? id,
    String? supplierName,
    String? supplierPhone,
    String? reference,
    double? total,
    double? amountPaid,
    String? paymentMethod,
    String? notes,
    String? purchaseDate,
    Value<String?> actorName = const Value.absent(),
    int? createdAt,
    int? updatedAt,
    bool? tombstone,
  }) => PurchaseEntry(
    id: id ?? this.id,
    supplierName: supplierName ?? this.supplierName,
    supplierPhone: supplierPhone ?? this.supplierPhone,
    reference: reference ?? this.reference,
    total: total ?? this.total,
    amountPaid: amountPaid ?? this.amountPaid,
    paymentMethod: paymentMethod ?? this.paymentMethod,
    notes: notes ?? this.notes,
    purchaseDate: purchaseDate ?? this.purchaseDate,
    actorName: actorName.present ? actorName.value : this.actorName,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    tombstone: tombstone ?? this.tombstone,
  );
  PurchaseEntry copyWithCompanion(PurchaseEntriesCompanion data) {
    return PurchaseEntry(
      id: data.id.present ? data.id.value : this.id,
      supplierName: data.supplierName.present
          ? data.supplierName.value
          : this.supplierName,
      supplierPhone: data.supplierPhone.present
          ? data.supplierPhone.value
          : this.supplierPhone,
      reference: data.reference.present ? data.reference.value : this.reference,
      total: data.total.present ? data.total.value : this.total,
      amountPaid: data.amountPaid.present
          ? data.amountPaid.value
          : this.amountPaid,
      paymentMethod: data.paymentMethod.present
          ? data.paymentMethod.value
          : this.paymentMethod,
      notes: data.notes.present ? data.notes.value : this.notes,
      purchaseDate: data.purchaseDate.present
          ? data.purchaseDate.value
          : this.purchaseDate,
      actorName: data.actorName.present ? data.actorName.value : this.actorName,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      tombstone: data.tombstone.present ? data.tombstone.value : this.tombstone,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PurchaseEntry(')
          ..write('id: $id, ')
          ..write('supplierName: $supplierName, ')
          ..write('supplierPhone: $supplierPhone, ')
          ..write('reference: $reference, ')
          ..write('total: $total, ')
          ..write('amountPaid: $amountPaid, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('notes: $notes, ')
          ..write('purchaseDate: $purchaseDate, ')
          ..write('actorName: $actorName, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('tombstone: $tombstone')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    supplierName,
    supplierPhone,
    reference,
    total,
    amountPaid,
    paymentMethod,
    notes,
    purchaseDate,
    actorName,
    createdAt,
    updatedAt,
    tombstone,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PurchaseEntry &&
          other.id == this.id &&
          other.supplierName == this.supplierName &&
          other.supplierPhone == this.supplierPhone &&
          other.reference == this.reference &&
          other.total == this.total &&
          other.amountPaid == this.amountPaid &&
          other.paymentMethod == this.paymentMethod &&
          other.notes == this.notes &&
          other.purchaseDate == this.purchaseDate &&
          other.actorName == this.actorName &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.tombstone == this.tombstone);
}

class PurchaseEntriesCompanion extends UpdateCompanion<PurchaseEntry> {
  final Value<String> id;
  final Value<String> supplierName;
  final Value<String> supplierPhone;
  final Value<String> reference;
  final Value<double> total;
  final Value<double> amountPaid;
  final Value<String> paymentMethod;
  final Value<String> notes;
  final Value<String> purchaseDate;
  final Value<String?> actorName;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<bool> tombstone;
  final Value<int> rowid;
  const PurchaseEntriesCompanion({
    this.id = const Value.absent(),
    this.supplierName = const Value.absent(),
    this.supplierPhone = const Value.absent(),
    this.reference = const Value.absent(),
    this.total = const Value.absent(),
    this.amountPaid = const Value.absent(),
    this.paymentMethod = const Value.absent(),
    this.notes = const Value.absent(),
    this.purchaseDate = const Value.absent(),
    this.actorName = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.tombstone = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PurchaseEntriesCompanion.insert({
    required String id,
    required String supplierName,
    this.supplierPhone = const Value.absent(),
    this.reference = const Value.absent(),
    this.total = const Value.absent(),
    this.amountPaid = const Value.absent(),
    this.paymentMethod = const Value.absent(),
    this.notes = const Value.absent(),
    required String purchaseDate,
    this.actorName = const Value.absent(),
    required int createdAt,
    this.updatedAt = const Value.absent(),
    this.tombstone = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       supplierName = Value(supplierName),
       purchaseDate = Value(purchaseDate),
       createdAt = Value(createdAt);
  static Insertable<PurchaseEntry> custom({
    Expression<String>? id,
    Expression<String>? supplierName,
    Expression<String>? supplierPhone,
    Expression<String>? reference,
    Expression<double>? total,
    Expression<double>? amountPaid,
    Expression<String>? paymentMethod,
    Expression<String>? notes,
    Expression<String>? purchaseDate,
    Expression<String>? actorName,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<bool>? tombstone,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (supplierName != null) 'supplier_name': supplierName,
      if (supplierPhone != null) 'supplier_phone': supplierPhone,
      if (reference != null) 'reference': reference,
      if (total != null) 'total': total,
      if (amountPaid != null) 'amount_paid': amountPaid,
      if (paymentMethod != null) 'payment_method': paymentMethod,
      if (notes != null) 'notes': notes,
      if (purchaseDate != null) 'purchase_date': purchaseDate,
      if (actorName != null) 'actor_name': actorName,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (tombstone != null) 'tombstone': tombstone,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PurchaseEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? supplierName,
    Value<String>? supplierPhone,
    Value<String>? reference,
    Value<double>? total,
    Value<double>? amountPaid,
    Value<String>? paymentMethod,
    Value<String>? notes,
    Value<String>? purchaseDate,
    Value<String?>? actorName,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<bool>? tombstone,
    Value<int>? rowid,
  }) {
    return PurchaseEntriesCompanion(
      id: id ?? this.id,
      supplierName: supplierName ?? this.supplierName,
      supplierPhone: supplierPhone ?? this.supplierPhone,
      reference: reference ?? this.reference,
      total: total ?? this.total,
      amountPaid: amountPaid ?? this.amountPaid,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      notes: notes ?? this.notes,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      actorName: actorName ?? this.actorName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      tombstone: tombstone ?? this.tombstone,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (supplierName.present) {
      map['supplier_name'] = Variable<String>(supplierName.value);
    }
    if (supplierPhone.present) {
      map['supplier_phone'] = Variable<String>(supplierPhone.value);
    }
    if (reference.present) {
      map['reference'] = Variable<String>(reference.value);
    }
    if (total.present) {
      map['total'] = Variable<double>(total.value);
    }
    if (amountPaid.present) {
      map['amount_paid'] = Variable<double>(amountPaid.value);
    }
    if (paymentMethod.present) {
      map['payment_method'] = Variable<String>(paymentMethod.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (purchaseDate.present) {
      map['purchase_date'] = Variable<String>(purchaseDate.value);
    }
    if (actorName.present) {
      map['actor_name'] = Variable<String>(actorName.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (tombstone.present) {
      map['tombstone'] = Variable<bool>(tombstone.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PurchaseEntriesCompanion(')
          ..write('id: $id, ')
          ..write('supplierName: $supplierName, ')
          ..write('supplierPhone: $supplierPhone, ')
          ..write('reference: $reference, ')
          ..write('total: $total, ')
          ..write('amountPaid: $amountPaid, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('notes: $notes, ')
          ..write('purchaseDate: $purchaseDate, ')
          ..write('actorName: $actorName, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('tombstone: $tombstone, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StockMovementEntriesTable extends StockMovementEntries
    with TableInfo<$StockMovementEntriesTable, StockMovementEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StockMovementEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _itemNameMeta = const VerificationMeta(
    'itemName',
  );
  @override
  late final GeneratedColumn<String> itemName = GeneratedColumn<String>(
    'item_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deltaMeta = const VerificationMeta('delta');
  @override
  late final GeneratedColumn<double> delta = GeneratedColumn<double>(
    'delta',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _balanceAfterMeta = const VerificationMeta(
    'balanceAfter',
  );
  @override
  late final GeneratedColumn<double> balanceAfter = GeneratedColumn<double>(
    'balance_after',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _refIdMeta = const VerificationMeta('refId');
  @override
  late final GeneratedColumn<String> refId = GeneratedColumn<String>(
    'ref_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _actorNameMeta = const VerificationMeta(
    'actorName',
  );
  @override
  late final GeneratedColumn<String> actorName = GeneratedColumn<String>(
    'actor_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    itemId,
    itemName,
    delta,
    balanceAfter,
    reason,
    refId,
    note,
    actorName,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stock_movements';
  @override
  VerificationContext validateIntegrity(
    Insertable<StockMovementEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('item_name')) {
      context.handle(
        _itemNameMeta,
        itemName.isAcceptableOrUnknown(data['item_name']!, _itemNameMeta),
      );
    } else if (isInserting) {
      context.missing(_itemNameMeta);
    }
    if (data.containsKey('delta')) {
      context.handle(
        _deltaMeta,
        delta.isAcceptableOrUnknown(data['delta']!, _deltaMeta),
      );
    } else if (isInserting) {
      context.missing(_deltaMeta);
    }
    if (data.containsKey('balance_after')) {
      context.handle(
        _balanceAfterMeta,
        balanceAfter.isAcceptableOrUnknown(
          data['balance_after']!,
          _balanceAfterMeta,
        ),
      );
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    } else if (isInserting) {
      context.missing(_reasonMeta);
    }
    if (data.containsKey('ref_id')) {
      context.handle(
        _refIdMeta,
        refId.isAcceptableOrUnknown(data['ref_id']!, _refIdMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('actor_name')) {
      context.handle(
        _actorNameMeta,
        actorName.isAcceptableOrUnknown(data['actor_name']!, _actorNameMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StockMovementEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StockMovementEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      )!,
      itemName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_name'],
      )!,
      delta: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}delta'],
      )!,
      balanceAfter: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}balance_after'],
      ),
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      )!,
      refId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ref_id'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      )!,
      actorName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}actor_name'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $StockMovementEntriesTable createAlias(String alias) {
    return $StockMovementEntriesTable(attachedDatabase, alias);
  }
}

class StockMovementEntry extends DataClass
    implements Insertable<StockMovementEntry> {
  final String id;
  final String itemId;
  final String itemName;
  final double delta;
  final double? balanceAfter;

  /// SALE | PURCHASE | RETURN | ADJUST | OPENING
  final String reason;
  final String? refId;
  final String note;
  final String? actorName;
  final int createdAt;
  const StockMovementEntry({
    required this.id,
    required this.itemId,
    required this.itemName,
    required this.delta,
    this.balanceAfter,
    required this.reason,
    this.refId,
    required this.note,
    this.actorName,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['item_id'] = Variable<String>(itemId);
    map['item_name'] = Variable<String>(itemName);
    map['delta'] = Variable<double>(delta);
    if (!nullToAbsent || balanceAfter != null) {
      map['balance_after'] = Variable<double>(balanceAfter);
    }
    map['reason'] = Variable<String>(reason);
    if (!nullToAbsent || refId != null) {
      map['ref_id'] = Variable<String>(refId);
    }
    map['note'] = Variable<String>(note);
    if (!nullToAbsent || actorName != null) {
      map['actor_name'] = Variable<String>(actorName);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  StockMovementEntriesCompanion toCompanion(bool nullToAbsent) {
    return StockMovementEntriesCompanion(
      id: Value(id),
      itemId: Value(itemId),
      itemName: Value(itemName),
      delta: Value(delta),
      balanceAfter: balanceAfter == null && nullToAbsent
          ? const Value.absent()
          : Value(balanceAfter),
      reason: Value(reason),
      refId: refId == null && nullToAbsent
          ? const Value.absent()
          : Value(refId),
      note: Value(note),
      actorName: actorName == null && nullToAbsent
          ? const Value.absent()
          : Value(actorName),
      createdAt: Value(createdAt),
    );
  }

  factory StockMovementEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StockMovementEntry(
      id: serializer.fromJson<String>(json['id']),
      itemId: serializer.fromJson<String>(json['itemId']),
      itemName: serializer.fromJson<String>(json['itemName']),
      delta: serializer.fromJson<double>(json['delta']),
      balanceAfter: serializer.fromJson<double?>(json['balanceAfter']),
      reason: serializer.fromJson<String>(json['reason']),
      refId: serializer.fromJson<String?>(json['refId']),
      note: serializer.fromJson<String>(json['note']),
      actorName: serializer.fromJson<String?>(json['actorName']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'itemId': serializer.toJson<String>(itemId),
      'itemName': serializer.toJson<String>(itemName),
      'delta': serializer.toJson<double>(delta),
      'balanceAfter': serializer.toJson<double?>(balanceAfter),
      'reason': serializer.toJson<String>(reason),
      'refId': serializer.toJson<String?>(refId),
      'note': serializer.toJson<String>(note),
      'actorName': serializer.toJson<String?>(actorName),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  StockMovementEntry copyWith({
    String? id,
    String? itemId,
    String? itemName,
    double? delta,
    Value<double?> balanceAfter = const Value.absent(),
    String? reason,
    Value<String?> refId = const Value.absent(),
    String? note,
    Value<String?> actorName = const Value.absent(),
    int? createdAt,
  }) => StockMovementEntry(
    id: id ?? this.id,
    itemId: itemId ?? this.itemId,
    itemName: itemName ?? this.itemName,
    delta: delta ?? this.delta,
    balanceAfter: balanceAfter.present ? balanceAfter.value : this.balanceAfter,
    reason: reason ?? this.reason,
    refId: refId.present ? refId.value : this.refId,
    note: note ?? this.note,
    actorName: actorName.present ? actorName.value : this.actorName,
    createdAt: createdAt ?? this.createdAt,
  );
  StockMovementEntry copyWithCompanion(StockMovementEntriesCompanion data) {
    return StockMovementEntry(
      id: data.id.present ? data.id.value : this.id,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      itemName: data.itemName.present ? data.itemName.value : this.itemName,
      delta: data.delta.present ? data.delta.value : this.delta,
      balanceAfter: data.balanceAfter.present
          ? data.balanceAfter.value
          : this.balanceAfter,
      reason: data.reason.present ? data.reason.value : this.reason,
      refId: data.refId.present ? data.refId.value : this.refId,
      note: data.note.present ? data.note.value : this.note,
      actorName: data.actorName.present ? data.actorName.value : this.actorName,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StockMovementEntry(')
          ..write('id: $id, ')
          ..write('itemId: $itemId, ')
          ..write('itemName: $itemName, ')
          ..write('delta: $delta, ')
          ..write('balanceAfter: $balanceAfter, ')
          ..write('reason: $reason, ')
          ..write('refId: $refId, ')
          ..write('note: $note, ')
          ..write('actorName: $actorName, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    itemId,
    itemName,
    delta,
    balanceAfter,
    reason,
    refId,
    note,
    actorName,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StockMovementEntry &&
          other.id == this.id &&
          other.itemId == this.itemId &&
          other.itemName == this.itemName &&
          other.delta == this.delta &&
          other.balanceAfter == this.balanceAfter &&
          other.reason == this.reason &&
          other.refId == this.refId &&
          other.note == this.note &&
          other.actorName == this.actorName &&
          other.createdAt == this.createdAt);
}

class StockMovementEntriesCompanion
    extends UpdateCompanion<StockMovementEntry> {
  final Value<String> id;
  final Value<String> itemId;
  final Value<String> itemName;
  final Value<double> delta;
  final Value<double?> balanceAfter;
  final Value<String> reason;
  final Value<String?> refId;
  final Value<String> note;
  final Value<String?> actorName;
  final Value<int> createdAt;
  final Value<int> rowid;
  const StockMovementEntriesCompanion({
    this.id = const Value.absent(),
    this.itemId = const Value.absent(),
    this.itemName = const Value.absent(),
    this.delta = const Value.absent(),
    this.balanceAfter = const Value.absent(),
    this.reason = const Value.absent(),
    this.refId = const Value.absent(),
    this.note = const Value.absent(),
    this.actorName = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StockMovementEntriesCompanion.insert({
    required String id,
    required String itemId,
    required String itemName,
    required double delta,
    this.balanceAfter = const Value.absent(),
    required String reason,
    this.refId = const Value.absent(),
    this.note = const Value.absent(),
    this.actorName = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       itemId = Value(itemId),
       itemName = Value(itemName),
       delta = Value(delta),
       reason = Value(reason),
       createdAt = Value(createdAt);
  static Insertable<StockMovementEntry> custom({
    Expression<String>? id,
    Expression<String>? itemId,
    Expression<String>? itemName,
    Expression<double>? delta,
    Expression<double>? balanceAfter,
    Expression<String>? reason,
    Expression<String>? refId,
    Expression<String>? note,
    Expression<String>? actorName,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (itemId != null) 'item_id': itemId,
      if (itemName != null) 'item_name': itemName,
      if (delta != null) 'delta': delta,
      if (balanceAfter != null) 'balance_after': balanceAfter,
      if (reason != null) 'reason': reason,
      if (refId != null) 'ref_id': refId,
      if (note != null) 'note': note,
      if (actorName != null) 'actor_name': actorName,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StockMovementEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? itemId,
    Value<String>? itemName,
    Value<double>? delta,
    Value<double?>? balanceAfter,
    Value<String>? reason,
    Value<String?>? refId,
    Value<String>? note,
    Value<String?>? actorName,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return StockMovementEntriesCompanion(
      id: id ?? this.id,
      itemId: itemId ?? this.itemId,
      itemName: itemName ?? this.itemName,
      delta: delta ?? this.delta,
      balanceAfter: balanceAfter ?? this.balanceAfter,
      reason: reason ?? this.reason,
      refId: refId ?? this.refId,
      note: note ?? this.note,
      actorName: actorName ?? this.actorName,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (itemName.present) {
      map['item_name'] = Variable<String>(itemName.value);
    }
    if (delta.present) {
      map['delta'] = Variable<double>(delta.value);
    }
    if (balanceAfter.present) {
      map['balance_after'] = Variable<double>(balanceAfter.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (refId.present) {
      map['ref_id'] = Variable<String>(refId.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (actorName.present) {
      map['actor_name'] = Variable<String>(actorName.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StockMovementEntriesCompanion(')
          ..write('id: $id, ')
          ..write('itemId: $itemId, ')
          ..write('itemName: $itemName, ')
          ..write('delta: $delta, ')
          ..write('balanceAfter: $balanceAfter, ')
          ..write('reason: $reason, ')
          ..write('refId: $refId, ')
          ..write('note: $note, ')
          ..write('actorName: $actorName, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CustomerLedgerEntriesTable extends CustomerLedgerEntries
    with TableInfo<$CustomerLedgerEntriesTable, CustomerLedgerEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CustomerLedgerEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _customerIdMeta = const VerificationMeta(
    'customerId',
  );
  @override
  late final GeneratedColumn<String> customerId = GeneratedColumn<String>(
    'customer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
    'amount',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _balanceAfterMeta = const VerificationMeta(
    'balanceAfter',
  );
  @override
  late final GeneratedColumn<double> balanceAfter = GeneratedColumn<double>(
    'balance_after',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _refIdMeta = const VerificationMeta('refId');
  @override
  late final GeneratedColumn<String> refId = GeneratedColumn<String>(
    'ref_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _actorNameMeta = const VerificationMeta(
    'actorName',
  );
  @override
  late final GeneratedColumn<String> actorName = GeneratedColumn<String>(
    'actor_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    customerId,
    type,
    amount,
    balanceAfter,
    refId,
    note,
    actorName,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'customer_ledger';
  @override
  VerificationContext validateIntegrity(
    Insertable<CustomerLedgerEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('customer_id')) {
      context.handle(
        _customerIdMeta,
        customerId.isAcceptableOrUnknown(data['customer_id']!, _customerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_customerIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('balance_after')) {
      context.handle(
        _balanceAfterMeta,
        balanceAfter.isAcceptableOrUnknown(
          data['balance_after']!,
          _balanceAfterMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_balanceAfterMeta);
    }
    if (data.containsKey('ref_id')) {
      context.handle(
        _refIdMeta,
        refId.isAcceptableOrUnknown(data['ref_id']!, _refIdMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('actor_name')) {
      context.handle(
        _actorNameMeta,
        actorName.isAcceptableOrUnknown(data['actor_name']!, _actorNameMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CustomerLedgerEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CustomerLedgerEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      customerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}customer_id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}amount'],
      )!,
      balanceAfter: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}balance_after'],
      )!,
      refId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ref_id'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      )!,
      actorName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}actor_name'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $CustomerLedgerEntriesTable createAlias(String alias) {
    return $CustomerLedgerEntriesTable(attachedDatabase, alias);
  }
}

class CustomerLedgerEntry extends DataClass
    implements Insertable<CustomerLedgerEntry> {
  final String id;
  final String customerId;
  final String type;
  final double amount;
  final double balanceAfter;
  final String? refId;
  final String note;
  final String? actorName;
  final int createdAt;
  const CustomerLedgerEntry({
    required this.id,
    required this.customerId,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    this.refId,
    required this.note,
    this.actorName,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['customer_id'] = Variable<String>(customerId);
    map['type'] = Variable<String>(type);
    map['amount'] = Variable<double>(amount);
    map['balance_after'] = Variable<double>(balanceAfter);
    if (!nullToAbsent || refId != null) {
      map['ref_id'] = Variable<String>(refId);
    }
    map['note'] = Variable<String>(note);
    if (!nullToAbsent || actorName != null) {
      map['actor_name'] = Variable<String>(actorName);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  CustomerLedgerEntriesCompanion toCompanion(bool nullToAbsent) {
    return CustomerLedgerEntriesCompanion(
      id: Value(id),
      customerId: Value(customerId),
      type: Value(type),
      amount: Value(amount),
      balanceAfter: Value(balanceAfter),
      refId: refId == null && nullToAbsent
          ? const Value.absent()
          : Value(refId),
      note: Value(note),
      actorName: actorName == null && nullToAbsent
          ? const Value.absent()
          : Value(actorName),
      createdAt: Value(createdAt),
    );
  }

  factory CustomerLedgerEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CustomerLedgerEntry(
      id: serializer.fromJson<String>(json['id']),
      customerId: serializer.fromJson<String>(json['customerId']),
      type: serializer.fromJson<String>(json['type']),
      amount: serializer.fromJson<double>(json['amount']),
      balanceAfter: serializer.fromJson<double>(json['balanceAfter']),
      refId: serializer.fromJson<String?>(json['refId']),
      note: serializer.fromJson<String>(json['note']),
      actorName: serializer.fromJson<String?>(json['actorName']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'customerId': serializer.toJson<String>(customerId),
      'type': serializer.toJson<String>(type),
      'amount': serializer.toJson<double>(amount),
      'balanceAfter': serializer.toJson<double>(balanceAfter),
      'refId': serializer.toJson<String?>(refId),
      'note': serializer.toJson<String>(note),
      'actorName': serializer.toJson<String?>(actorName),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  CustomerLedgerEntry copyWith({
    String? id,
    String? customerId,
    String? type,
    double? amount,
    double? balanceAfter,
    Value<String?> refId = const Value.absent(),
    String? note,
    Value<String?> actorName = const Value.absent(),
    int? createdAt,
  }) => CustomerLedgerEntry(
    id: id ?? this.id,
    customerId: customerId ?? this.customerId,
    type: type ?? this.type,
    amount: amount ?? this.amount,
    balanceAfter: balanceAfter ?? this.balanceAfter,
    refId: refId.present ? refId.value : this.refId,
    note: note ?? this.note,
    actorName: actorName.present ? actorName.value : this.actorName,
    createdAt: createdAt ?? this.createdAt,
  );
  CustomerLedgerEntry copyWithCompanion(CustomerLedgerEntriesCompanion data) {
    return CustomerLedgerEntry(
      id: data.id.present ? data.id.value : this.id,
      customerId: data.customerId.present
          ? data.customerId.value
          : this.customerId,
      type: data.type.present ? data.type.value : this.type,
      amount: data.amount.present ? data.amount.value : this.amount,
      balanceAfter: data.balanceAfter.present
          ? data.balanceAfter.value
          : this.balanceAfter,
      refId: data.refId.present ? data.refId.value : this.refId,
      note: data.note.present ? data.note.value : this.note,
      actorName: data.actorName.present ? data.actorName.value : this.actorName,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CustomerLedgerEntry(')
          ..write('id: $id, ')
          ..write('customerId: $customerId, ')
          ..write('type: $type, ')
          ..write('amount: $amount, ')
          ..write('balanceAfter: $balanceAfter, ')
          ..write('refId: $refId, ')
          ..write('note: $note, ')
          ..write('actorName: $actorName, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    customerId,
    type,
    amount,
    balanceAfter,
    refId,
    note,
    actorName,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CustomerLedgerEntry &&
          other.id == this.id &&
          other.customerId == this.customerId &&
          other.type == this.type &&
          other.amount == this.amount &&
          other.balanceAfter == this.balanceAfter &&
          other.refId == this.refId &&
          other.note == this.note &&
          other.actorName == this.actorName &&
          other.createdAt == this.createdAt);
}

class CustomerLedgerEntriesCompanion
    extends UpdateCompanion<CustomerLedgerEntry> {
  final Value<String> id;
  final Value<String> customerId;
  final Value<String> type;
  final Value<double> amount;
  final Value<double> balanceAfter;
  final Value<String?> refId;
  final Value<String> note;
  final Value<String?> actorName;
  final Value<int> createdAt;
  final Value<int> rowid;
  const CustomerLedgerEntriesCompanion({
    this.id = const Value.absent(),
    this.customerId = const Value.absent(),
    this.type = const Value.absent(),
    this.amount = const Value.absent(),
    this.balanceAfter = const Value.absent(),
    this.refId = const Value.absent(),
    this.note = const Value.absent(),
    this.actorName = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CustomerLedgerEntriesCompanion.insert({
    required String id,
    required String customerId,
    required String type,
    required double amount,
    required double balanceAfter,
    this.refId = const Value.absent(),
    this.note = const Value.absent(),
    this.actorName = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       customerId = Value(customerId),
       type = Value(type),
       amount = Value(amount),
       balanceAfter = Value(balanceAfter),
       createdAt = Value(createdAt);
  static Insertable<CustomerLedgerEntry> custom({
    Expression<String>? id,
    Expression<String>? customerId,
    Expression<String>? type,
    Expression<double>? amount,
    Expression<double>? balanceAfter,
    Expression<String>? refId,
    Expression<String>? note,
    Expression<String>? actorName,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (customerId != null) 'customer_id': customerId,
      if (type != null) 'type': type,
      if (amount != null) 'amount': amount,
      if (balanceAfter != null) 'balance_after': balanceAfter,
      if (refId != null) 'ref_id': refId,
      if (note != null) 'note': note,
      if (actorName != null) 'actor_name': actorName,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CustomerLedgerEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? customerId,
    Value<String>? type,
    Value<double>? amount,
    Value<double>? balanceAfter,
    Value<String?>? refId,
    Value<String>? note,
    Value<String?>? actorName,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return CustomerLedgerEntriesCompanion(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      balanceAfter: balanceAfter ?? this.balanceAfter,
      refId: refId ?? this.refId,
      note: note ?? this.note,
      actorName: actorName ?? this.actorName,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (customerId.present) {
      map['customer_id'] = Variable<String>(customerId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (amount.present) {
      map['amount'] = Variable<double>(amount.value);
    }
    if (balanceAfter.present) {
      map['balance_after'] = Variable<double>(balanceAfter.value);
    }
    if (refId.present) {
      map['ref_id'] = Variable<String>(refId.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (actorName.present) {
      map['actor_name'] = Variable<String>(actorName.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CustomerLedgerEntriesCompanion(')
          ..write('id: $id, ')
          ..write('customerId: $customerId, ')
          ..write('type: $type, ')
          ..write('amount: $amount, ')
          ..write('balanceAfter: $balanceAfter, ')
          ..write('refId: $refId, ')
          ..write('note: $note, ')
          ..write('actorName: $actorName, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$BusinessHubDatabase extends GeneratedDatabase {
  _$BusinessHubDatabase(QueryExecutor e) : super(e);
  $BusinessHubDatabaseManager get managers => $BusinessHubDatabaseManager(this);
  late final $ShopSettingsEntriesTable shopSettingsEntries =
      $ShopSettingsEntriesTable(this);
  late final $InventoryEntriesTable inventoryEntries = $InventoryEntriesTable(
    this,
  );
  late final $InventoryPrivateEntriesTable inventoryPrivateEntries =
      $InventoryPrivateEntriesTable(this);
  late final $SalesEntriesTable salesEntries = $SalesEntriesTable(this);
  late final $CustomerEntriesTable customerEntries = $CustomerEntriesTable(
    this,
  );
  late final $CommerceOutboxEntriesTable commerceOutboxEntries =
      $CommerceOutboxEntriesTable(this);
  late final $ExpenseEntriesTable expenseEntries = $ExpenseEntriesTable(this);
  late final $PurchaseEntriesTable purchaseEntries = $PurchaseEntriesTable(
    this,
  );
  late final $StockMovementEntriesTable stockMovementEntries =
      $StockMovementEntriesTable(this);
  late final $CustomerLedgerEntriesTable customerLedgerEntries =
      $CustomerLedgerEntriesTable(this);
  late final Index inventoryNameIdx = Index(
    'inventory_name_idx',
    'CREATE INDEX inventory_name_idx ON inventory (name)',
  );
  late final Index inventorySkuIdx = Index(
    'inventory_sku_idx',
    'CREATE INDEX inventory_sku_idx ON inventory (sku)',
  );
  late final Index inventoryCategoryIdx = Index(
    'inventory_category_idx',
    'CREATE INDEX inventory_category_idx ON inventory (category)',
  );
  late final Index inventoryTombstoneIdx = Index(
    'inventory_tombstone_idx',
    'CREATE INDEX inventory_tombstone_idx ON inventory (tombstone)',
  );
  late final Index salesCreatedAtIdx = Index(
    'sales_created_at_idx',
    'CREATE INDEX sales_created_at_idx ON sales (created_at)',
  );
  late final Index salesTombstoneIdx = Index(
    'sales_tombstone_idx',
    'CREATE INDEX sales_tombstone_idx ON sales (tombstone)',
  );
  late final Index salesSyncStatusIdx = Index(
    'sales_sync_status_idx',
    'CREATE INDEX sales_sync_status_idx ON sales (sync_status)',
  );
  late final Index customersNameIdx = Index(
    'customers_name_idx',
    'CREATE INDEX customers_name_idx ON customers (name)',
  );
  late final Index customersPhoneIdx = Index(
    'customers_phone_idx',
    'CREATE INDEX customers_phone_idx ON customers (phone)',
  );
  late final Index customersTombstoneIdx = Index(
    'customers_tombstone_idx',
    'CREATE INDEX customers_tombstone_idx ON customers (tombstone)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    shopSettingsEntries,
    inventoryEntries,
    inventoryPrivateEntries,
    salesEntries,
    customerEntries,
    commerceOutboxEntries,
    expenseEntries,
    purchaseEntries,
    stockMovementEntries,
    customerLedgerEntries,
    inventoryNameIdx,
    inventorySkuIdx,
    inventoryCategoryIdx,
    inventoryTombstoneIdx,
    salesCreatedAtIdx,
    salesTombstoneIdx,
    salesSyncStatusIdx,
    customersNameIdx,
    customersPhoneIdx,
    customersTombstoneIdx,
  ];
}

typedef $$ShopSettingsEntriesTableCreateCompanionBuilder =
    ShopSettingsEntriesCompanion Function({
      required String key,
      required String value,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$ShopSettingsEntriesTableUpdateCompanionBuilder =
    ShopSettingsEntriesCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$ShopSettingsEntriesTableFilterComposer
    extends Composer<_$BusinessHubDatabase, $ShopSettingsEntriesTable> {
  $$ShopSettingsEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ShopSettingsEntriesTableOrderingComposer
    extends Composer<_$BusinessHubDatabase, $ShopSettingsEntriesTable> {
  $$ShopSettingsEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ShopSettingsEntriesTableAnnotationComposer
    extends Composer<_$BusinessHubDatabase, $ShopSettingsEntriesTable> {
  $$ShopSettingsEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ShopSettingsEntriesTableTableManager
    extends
        RootTableManager<
          _$BusinessHubDatabase,
          $ShopSettingsEntriesTable,
          ShopSettingsEntry,
          $$ShopSettingsEntriesTableFilterComposer,
          $$ShopSettingsEntriesTableOrderingComposer,
          $$ShopSettingsEntriesTableAnnotationComposer,
          $$ShopSettingsEntriesTableCreateCompanionBuilder,
          $$ShopSettingsEntriesTableUpdateCompanionBuilder,
          (
            ShopSettingsEntry,
            BaseReferences<
              _$BusinessHubDatabase,
              $ShopSettingsEntriesTable,
              ShopSettingsEntry
            >,
          ),
          ShopSettingsEntry,
          PrefetchHooks Function()
        > {
  $$ShopSettingsEntriesTableTableManager(
    _$BusinessHubDatabase db,
    $ShopSettingsEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ShopSettingsEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ShopSettingsEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ShopSettingsEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ShopSettingsEntriesCompanion(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ShopSettingsEntriesCompanion.insert(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ShopSettingsEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$BusinessHubDatabase,
      $ShopSettingsEntriesTable,
      ShopSettingsEntry,
      $$ShopSettingsEntriesTableFilterComposer,
      $$ShopSettingsEntriesTableOrderingComposer,
      $$ShopSettingsEntriesTableAnnotationComposer,
      $$ShopSettingsEntriesTableCreateCompanionBuilder,
      $$ShopSettingsEntriesTableUpdateCompanionBuilder,
      (
        ShopSettingsEntry,
        BaseReferences<
          _$BusinessHubDatabase,
          $ShopSettingsEntriesTable,
          ShopSettingsEntry
        >,
      ),
      ShopSettingsEntry,
      PrefetchHooks Function()
    >;
typedef $$InventoryEntriesTableCreateCompanionBuilder =
    InventoryEntriesCompanion Function({
      required String id,
      required String name,
      required double price,
      Value<String?> sku,
      Value<String?> barcode,
      Value<String> category,
      Value<String?> subcategory,
      Value<String?> size,
      Value<String?> description,
      Value<String?> hsnCode,
      Value<double> gstRate,
      Value<bool> priceIncludesTax,
      Value<double> stock,
      Value<String?> sourceMeta,
      Value<String?> imagePath,
      Value<String?> unit,
      Value<int?> reorderLevel,
      Value<bool?> hasStockHistory,
      Value<String?> variantGroupId,
      Value<String?> variantLabel,
      required int createdAt,
      Value<int> updatedAt,
      Value<bool> tombstone,
      Value<int> rowid,
    });
typedef $$InventoryEntriesTableUpdateCompanionBuilder =
    InventoryEntriesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<double> price,
      Value<String?> sku,
      Value<String?> barcode,
      Value<String> category,
      Value<String?> subcategory,
      Value<String?> size,
      Value<String?> description,
      Value<String?> hsnCode,
      Value<double> gstRate,
      Value<bool> priceIncludesTax,
      Value<double> stock,
      Value<String?> sourceMeta,
      Value<String?> imagePath,
      Value<String?> unit,
      Value<int?> reorderLevel,
      Value<bool?> hasStockHistory,
      Value<String?> variantGroupId,
      Value<String?> variantLabel,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<bool> tombstone,
      Value<int> rowid,
    });

class $$InventoryEntriesTableFilterComposer
    extends Composer<_$BusinessHubDatabase, $InventoryEntriesTable> {
  $$InventoryEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sku => $composableBuilder(
    column: $table.sku,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get barcode => $composableBuilder(
    column: $table.barcode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subcategory => $composableBuilder(
    column: $table.subcategory,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hsnCode => $composableBuilder(
    column: $table.hsnCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get gstRate => $composableBuilder(
    column: $table.gstRate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get priceIncludesTax => $composableBuilder(
    column: $table.priceIncludesTax,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get stock => $composableBuilder(
    column: $table.stock,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceMeta => $composableBuilder(
    column: $table.sourceMeta,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imagePath => $composableBuilder(
    column: $table.imagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reorderLevel => $composableBuilder(
    column: $table.reorderLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hasStockHistory => $composableBuilder(
    column: $table.hasStockHistory,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get variantGroupId => $composableBuilder(
    column: $table.variantGroupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get variantLabel => $composableBuilder(
    column: $table.variantLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get tombstone => $composableBuilder(
    column: $table.tombstone,
    builder: (column) => ColumnFilters(column),
  );
}

class $$InventoryEntriesTableOrderingComposer
    extends Composer<_$BusinessHubDatabase, $InventoryEntriesTable> {
  $$InventoryEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sku => $composableBuilder(
    column: $table.sku,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get barcode => $composableBuilder(
    column: $table.barcode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subcategory => $composableBuilder(
    column: $table.subcategory,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hsnCode => $composableBuilder(
    column: $table.hsnCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get gstRate => $composableBuilder(
    column: $table.gstRate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get priceIncludesTax => $composableBuilder(
    column: $table.priceIncludesTax,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get stock => $composableBuilder(
    column: $table.stock,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceMeta => $composableBuilder(
    column: $table.sourceMeta,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imagePath => $composableBuilder(
    column: $table.imagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reorderLevel => $composableBuilder(
    column: $table.reorderLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hasStockHistory => $composableBuilder(
    column: $table.hasStockHistory,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get variantGroupId => $composableBuilder(
    column: $table.variantGroupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get variantLabel => $composableBuilder(
    column: $table.variantLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get tombstone => $composableBuilder(
    column: $table.tombstone,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$InventoryEntriesTableAnnotationComposer
    extends Composer<_$BusinessHubDatabase, $InventoryEntriesTable> {
  $$InventoryEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<double> get price =>
      $composableBuilder(column: $table.price, builder: (column) => column);

  GeneratedColumn<String> get sku =>
      $composableBuilder(column: $table.sku, builder: (column) => column);

  GeneratedColumn<String> get barcode =>
      $composableBuilder(column: $table.barcode, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get subcategory => $composableBuilder(
    column: $table.subcategory,
    builder: (column) => column,
  );

  GeneratedColumn<String> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get hsnCode =>
      $composableBuilder(column: $table.hsnCode, builder: (column) => column);

  GeneratedColumn<double> get gstRate =>
      $composableBuilder(column: $table.gstRate, builder: (column) => column);

  GeneratedColumn<bool> get priceIncludesTax => $composableBuilder(
    column: $table.priceIncludesTax,
    builder: (column) => column,
  );

  GeneratedColumn<double> get stock =>
      $composableBuilder(column: $table.stock, builder: (column) => column);

  GeneratedColumn<String> get sourceMeta => $composableBuilder(
    column: $table.sourceMeta,
    builder: (column) => column,
  );

  GeneratedColumn<String> get imagePath =>
      $composableBuilder(column: $table.imagePath, builder: (column) => column);

  GeneratedColumn<String> get unit =>
      $composableBuilder(column: $table.unit, builder: (column) => column);

  GeneratedColumn<int> get reorderLevel => $composableBuilder(
    column: $table.reorderLevel,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get hasStockHistory => $composableBuilder(
    column: $table.hasStockHistory,
    builder: (column) => column,
  );

  GeneratedColumn<String> get variantGroupId => $composableBuilder(
    column: $table.variantGroupId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get variantLabel => $composableBuilder(
    column: $table.variantLabel,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get tombstone =>
      $composableBuilder(column: $table.tombstone, builder: (column) => column);
}

class $$InventoryEntriesTableTableManager
    extends
        RootTableManager<
          _$BusinessHubDatabase,
          $InventoryEntriesTable,
          InventoryEntry,
          $$InventoryEntriesTableFilterComposer,
          $$InventoryEntriesTableOrderingComposer,
          $$InventoryEntriesTableAnnotationComposer,
          $$InventoryEntriesTableCreateCompanionBuilder,
          $$InventoryEntriesTableUpdateCompanionBuilder,
          (
            InventoryEntry,
            BaseReferences<
              _$BusinessHubDatabase,
              $InventoryEntriesTable,
              InventoryEntry
            >,
          ),
          InventoryEntry,
          PrefetchHooks Function()
        > {
  $$InventoryEntriesTableTableManager(
    _$BusinessHubDatabase db,
    $InventoryEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InventoryEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InventoryEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$InventoryEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<double> price = const Value.absent(),
                Value<String?> sku = const Value.absent(),
                Value<String?> barcode = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<String?> subcategory = const Value.absent(),
                Value<String?> size = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String?> hsnCode = const Value.absent(),
                Value<double> gstRate = const Value.absent(),
                Value<bool> priceIncludesTax = const Value.absent(),
                Value<double> stock = const Value.absent(),
                Value<String?> sourceMeta = const Value.absent(),
                Value<String?> imagePath = const Value.absent(),
                Value<String?> unit = const Value.absent(),
                Value<int?> reorderLevel = const Value.absent(),
                Value<bool?> hasStockHistory = const Value.absent(),
                Value<String?> variantGroupId = const Value.absent(),
                Value<String?> variantLabel = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<bool> tombstone = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InventoryEntriesCompanion(
                id: id,
                name: name,
                price: price,
                sku: sku,
                barcode: barcode,
                category: category,
                subcategory: subcategory,
                size: size,
                description: description,
                hsnCode: hsnCode,
                gstRate: gstRate,
                priceIncludesTax: priceIncludesTax,
                stock: stock,
                sourceMeta: sourceMeta,
                imagePath: imagePath,
                unit: unit,
                reorderLevel: reorderLevel,
                hasStockHistory: hasStockHistory,
                variantGroupId: variantGroupId,
                variantLabel: variantLabel,
                createdAt: createdAt,
                updatedAt: updatedAt,
                tombstone: tombstone,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required double price,
                Value<String?> sku = const Value.absent(),
                Value<String?> barcode = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<String?> subcategory = const Value.absent(),
                Value<String?> size = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String?> hsnCode = const Value.absent(),
                Value<double> gstRate = const Value.absent(),
                Value<bool> priceIncludesTax = const Value.absent(),
                Value<double> stock = const Value.absent(),
                Value<String?> sourceMeta = const Value.absent(),
                Value<String?> imagePath = const Value.absent(),
                Value<String?> unit = const Value.absent(),
                Value<int?> reorderLevel = const Value.absent(),
                Value<bool?> hasStockHistory = const Value.absent(),
                Value<String?> variantGroupId = const Value.absent(),
                Value<String?> variantLabel = const Value.absent(),
                required int createdAt,
                Value<int> updatedAt = const Value.absent(),
                Value<bool> tombstone = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InventoryEntriesCompanion.insert(
                id: id,
                name: name,
                price: price,
                sku: sku,
                barcode: barcode,
                category: category,
                subcategory: subcategory,
                size: size,
                description: description,
                hsnCode: hsnCode,
                gstRate: gstRate,
                priceIncludesTax: priceIncludesTax,
                stock: stock,
                sourceMeta: sourceMeta,
                imagePath: imagePath,
                unit: unit,
                reorderLevel: reorderLevel,
                hasStockHistory: hasStockHistory,
                variantGroupId: variantGroupId,
                variantLabel: variantLabel,
                createdAt: createdAt,
                updatedAt: updatedAt,
                tombstone: tombstone,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$InventoryEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$BusinessHubDatabase,
      $InventoryEntriesTable,
      InventoryEntry,
      $$InventoryEntriesTableFilterComposer,
      $$InventoryEntriesTableOrderingComposer,
      $$InventoryEntriesTableAnnotationComposer,
      $$InventoryEntriesTableCreateCompanionBuilder,
      $$InventoryEntriesTableUpdateCompanionBuilder,
      (
        InventoryEntry,
        BaseReferences<
          _$BusinessHubDatabase,
          $InventoryEntriesTable,
          InventoryEntry
        >,
      ),
      InventoryEntry,
      PrefetchHooks Function()
    >;
typedef $$InventoryPrivateEntriesTableCreateCompanionBuilder =
    InventoryPrivateEntriesCompanion Function({
      required String id,
      Value<double> costPrice,
      Value<String?> supplierId,
      Value<String?> lastPurchaseDate,
      Value<int> updatedAt,
      Value<bool> tombstone,
      Value<int> rowid,
    });
typedef $$InventoryPrivateEntriesTableUpdateCompanionBuilder =
    InventoryPrivateEntriesCompanion Function({
      Value<String> id,
      Value<double> costPrice,
      Value<String?> supplierId,
      Value<String?> lastPurchaseDate,
      Value<int> updatedAt,
      Value<bool> tombstone,
      Value<int> rowid,
    });

class $$InventoryPrivateEntriesTableFilterComposer
    extends Composer<_$BusinessHubDatabase, $InventoryPrivateEntriesTable> {
  $$InventoryPrivateEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get costPrice => $composableBuilder(
    column: $table.costPrice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get supplierId => $composableBuilder(
    column: $table.supplierId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastPurchaseDate => $composableBuilder(
    column: $table.lastPurchaseDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get tombstone => $composableBuilder(
    column: $table.tombstone,
    builder: (column) => ColumnFilters(column),
  );
}

class $$InventoryPrivateEntriesTableOrderingComposer
    extends Composer<_$BusinessHubDatabase, $InventoryPrivateEntriesTable> {
  $$InventoryPrivateEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get costPrice => $composableBuilder(
    column: $table.costPrice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get supplierId => $composableBuilder(
    column: $table.supplierId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastPurchaseDate => $composableBuilder(
    column: $table.lastPurchaseDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get tombstone => $composableBuilder(
    column: $table.tombstone,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$InventoryPrivateEntriesTableAnnotationComposer
    extends Composer<_$BusinessHubDatabase, $InventoryPrivateEntriesTable> {
  $$InventoryPrivateEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get costPrice =>
      $composableBuilder(column: $table.costPrice, builder: (column) => column);

  GeneratedColumn<String> get supplierId => $composableBuilder(
    column: $table.supplierId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastPurchaseDate => $composableBuilder(
    column: $table.lastPurchaseDate,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get tombstone =>
      $composableBuilder(column: $table.tombstone, builder: (column) => column);
}

class $$InventoryPrivateEntriesTableTableManager
    extends
        RootTableManager<
          _$BusinessHubDatabase,
          $InventoryPrivateEntriesTable,
          InventoryPrivateEntry,
          $$InventoryPrivateEntriesTableFilterComposer,
          $$InventoryPrivateEntriesTableOrderingComposer,
          $$InventoryPrivateEntriesTableAnnotationComposer,
          $$InventoryPrivateEntriesTableCreateCompanionBuilder,
          $$InventoryPrivateEntriesTableUpdateCompanionBuilder,
          (
            InventoryPrivateEntry,
            BaseReferences<
              _$BusinessHubDatabase,
              $InventoryPrivateEntriesTable,
              InventoryPrivateEntry
            >,
          ),
          InventoryPrivateEntry,
          PrefetchHooks Function()
        > {
  $$InventoryPrivateEntriesTableTableManager(
    _$BusinessHubDatabase db,
    $InventoryPrivateEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InventoryPrivateEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$InventoryPrivateEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$InventoryPrivateEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<double> costPrice = const Value.absent(),
                Value<String?> supplierId = const Value.absent(),
                Value<String?> lastPurchaseDate = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<bool> tombstone = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InventoryPrivateEntriesCompanion(
                id: id,
                costPrice: costPrice,
                supplierId: supplierId,
                lastPurchaseDate: lastPurchaseDate,
                updatedAt: updatedAt,
                tombstone: tombstone,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<double> costPrice = const Value.absent(),
                Value<String?> supplierId = const Value.absent(),
                Value<String?> lastPurchaseDate = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<bool> tombstone = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InventoryPrivateEntriesCompanion.insert(
                id: id,
                costPrice: costPrice,
                supplierId: supplierId,
                lastPurchaseDate: lastPurchaseDate,
                updatedAt: updatedAt,
                tombstone: tombstone,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$InventoryPrivateEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$BusinessHubDatabase,
      $InventoryPrivateEntriesTable,
      InventoryPrivateEntry,
      $$InventoryPrivateEntriesTableFilterComposer,
      $$InventoryPrivateEntriesTableOrderingComposer,
      $$InventoryPrivateEntriesTableAnnotationComposer,
      $$InventoryPrivateEntriesTableCreateCompanionBuilder,
      $$InventoryPrivateEntriesTableUpdateCompanionBuilder,
      (
        InventoryPrivateEntry,
        BaseReferences<
          _$BusinessHubDatabase,
          $InventoryPrivateEntriesTable,
          InventoryPrivateEntry
        >,
      ),
      InventoryPrivateEntry,
      PrefetchHooks Function()
    >;
typedef $$SalesEntriesTableCreateCompanionBuilder =
    SalesEntriesCompanion Function({
      required String id,
      required double total,
      Value<double> discount,
      Value<String> discountType,
      Value<String> paymentMode,
      required String date,
      required int createdAt,
      Value<int> updatedAt,
      Value<String?> customerName,
      Value<String?> customerPhone,
      Value<String?> customerId,
      Value<String?> footerNote,
      required String itemsJson,
      required String paymentsJson,
      Value<String?> commandId,
      Value<String> syncStatus,
      Value<String?> backendReceiptId,
      Value<String?> backendSaleId,
      Value<String?> lastSyncError,
      Value<int?> lastSyncedAt,
      Value<bool> tombstone,
      Value<int> rowid,
    });
typedef $$SalesEntriesTableUpdateCompanionBuilder =
    SalesEntriesCompanion Function({
      Value<String> id,
      Value<double> total,
      Value<double> discount,
      Value<String> discountType,
      Value<String> paymentMode,
      Value<String> date,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<String?> customerName,
      Value<String?> customerPhone,
      Value<String?> customerId,
      Value<String?> footerNote,
      Value<String> itemsJson,
      Value<String> paymentsJson,
      Value<String?> commandId,
      Value<String> syncStatus,
      Value<String?> backendReceiptId,
      Value<String?> backendSaleId,
      Value<String?> lastSyncError,
      Value<int?> lastSyncedAt,
      Value<bool> tombstone,
      Value<int> rowid,
    });

class $$SalesEntriesTableFilterComposer
    extends Composer<_$BusinessHubDatabase, $SalesEntriesTable> {
  $$SalesEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get total => $composableBuilder(
    column: $table.total,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get discount => $composableBuilder(
    column: $table.discount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get discountType => $composableBuilder(
    column: $table.discountType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get paymentMode => $composableBuilder(
    column: $table.paymentMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customerName => $composableBuilder(
    column: $table.customerName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customerPhone => $composableBuilder(
    column: $table.customerPhone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customerId => $composableBuilder(
    column: $table.customerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get footerNote => $composableBuilder(
    column: $table.footerNote,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get itemsJson => $composableBuilder(
    column: $table.itemsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get paymentsJson => $composableBuilder(
    column: $table.paymentsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get commandId => $composableBuilder(
    column: $table.commandId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get backendReceiptId => $composableBuilder(
    column: $table.backendReceiptId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get backendSaleId => $composableBuilder(
    column: $table.backendSaleId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastSyncError => $composableBuilder(
    column: $table.lastSyncError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get tombstone => $composableBuilder(
    column: $table.tombstone,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SalesEntriesTableOrderingComposer
    extends Composer<_$BusinessHubDatabase, $SalesEntriesTable> {
  $$SalesEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get total => $composableBuilder(
    column: $table.total,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get discount => $composableBuilder(
    column: $table.discount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get discountType => $composableBuilder(
    column: $table.discountType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paymentMode => $composableBuilder(
    column: $table.paymentMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customerName => $composableBuilder(
    column: $table.customerName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customerPhone => $composableBuilder(
    column: $table.customerPhone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customerId => $composableBuilder(
    column: $table.customerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get footerNote => $composableBuilder(
    column: $table.footerNote,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get itemsJson => $composableBuilder(
    column: $table.itemsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paymentsJson => $composableBuilder(
    column: $table.paymentsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get commandId => $composableBuilder(
    column: $table.commandId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get backendReceiptId => $composableBuilder(
    column: $table.backendReceiptId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get backendSaleId => $composableBuilder(
    column: $table.backendSaleId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastSyncError => $composableBuilder(
    column: $table.lastSyncError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get tombstone => $composableBuilder(
    column: $table.tombstone,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SalesEntriesTableAnnotationComposer
    extends Composer<_$BusinessHubDatabase, $SalesEntriesTable> {
  $$SalesEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get total =>
      $composableBuilder(column: $table.total, builder: (column) => column);

  GeneratedColumn<double> get discount =>
      $composableBuilder(column: $table.discount, builder: (column) => column);

  GeneratedColumn<String> get discountType => $composableBuilder(
    column: $table.discountType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get paymentMode => $composableBuilder(
    column: $table.paymentMode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get customerName => $composableBuilder(
    column: $table.customerName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get customerPhone => $composableBuilder(
    column: $table.customerPhone,
    builder: (column) => column,
  );

  GeneratedColumn<String> get customerId => $composableBuilder(
    column: $table.customerId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get footerNote => $composableBuilder(
    column: $table.footerNote,
    builder: (column) => column,
  );

  GeneratedColumn<String> get itemsJson =>
      $composableBuilder(column: $table.itemsJson, builder: (column) => column);

  GeneratedColumn<String> get paymentsJson => $composableBuilder(
    column: $table.paymentsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get commandId =>
      $composableBuilder(column: $table.commandId, builder: (column) => column);

  GeneratedColumn<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get backendReceiptId => $composableBuilder(
    column: $table.backendReceiptId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get backendSaleId => $composableBuilder(
    column: $table.backendSaleId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastSyncError => $composableBuilder(
    column: $table.lastSyncError,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get tombstone =>
      $composableBuilder(column: $table.tombstone, builder: (column) => column);
}

class $$SalesEntriesTableTableManager
    extends
        RootTableManager<
          _$BusinessHubDatabase,
          $SalesEntriesTable,
          SalesEntry,
          $$SalesEntriesTableFilterComposer,
          $$SalesEntriesTableOrderingComposer,
          $$SalesEntriesTableAnnotationComposer,
          $$SalesEntriesTableCreateCompanionBuilder,
          $$SalesEntriesTableUpdateCompanionBuilder,
          (
            SalesEntry,
            BaseReferences<
              _$BusinessHubDatabase,
              $SalesEntriesTable,
              SalesEntry
            >,
          ),
          SalesEntry,
          PrefetchHooks Function()
        > {
  $$SalesEntriesTableTableManager(
    _$BusinessHubDatabase db,
    $SalesEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SalesEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SalesEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SalesEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<double> total = const Value.absent(),
                Value<double> discount = const Value.absent(),
                Value<String> discountType = const Value.absent(),
                Value<String> paymentMode = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String?> customerName = const Value.absent(),
                Value<String?> customerPhone = const Value.absent(),
                Value<String?> customerId = const Value.absent(),
                Value<String?> footerNote = const Value.absent(),
                Value<String> itemsJson = const Value.absent(),
                Value<String> paymentsJson = const Value.absent(),
                Value<String?> commandId = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<String?> backendReceiptId = const Value.absent(),
                Value<String?> backendSaleId = const Value.absent(),
                Value<String?> lastSyncError = const Value.absent(),
                Value<int?> lastSyncedAt = const Value.absent(),
                Value<bool> tombstone = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SalesEntriesCompanion(
                id: id,
                total: total,
                discount: discount,
                discountType: discountType,
                paymentMode: paymentMode,
                date: date,
                createdAt: createdAt,
                updatedAt: updatedAt,
                customerName: customerName,
                customerPhone: customerPhone,
                customerId: customerId,
                footerNote: footerNote,
                itemsJson: itemsJson,
                paymentsJson: paymentsJson,
                commandId: commandId,
                syncStatus: syncStatus,
                backendReceiptId: backendReceiptId,
                backendSaleId: backendSaleId,
                lastSyncError: lastSyncError,
                lastSyncedAt: lastSyncedAt,
                tombstone: tombstone,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required double total,
                Value<double> discount = const Value.absent(),
                Value<String> discountType = const Value.absent(),
                Value<String> paymentMode = const Value.absent(),
                required String date,
                required int createdAt,
                Value<int> updatedAt = const Value.absent(),
                Value<String?> customerName = const Value.absent(),
                Value<String?> customerPhone = const Value.absent(),
                Value<String?> customerId = const Value.absent(),
                Value<String?> footerNote = const Value.absent(),
                required String itemsJson,
                required String paymentsJson,
                Value<String?> commandId = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<String?> backendReceiptId = const Value.absent(),
                Value<String?> backendSaleId = const Value.absent(),
                Value<String?> lastSyncError = const Value.absent(),
                Value<int?> lastSyncedAt = const Value.absent(),
                Value<bool> tombstone = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SalesEntriesCompanion.insert(
                id: id,
                total: total,
                discount: discount,
                discountType: discountType,
                paymentMode: paymentMode,
                date: date,
                createdAt: createdAt,
                updatedAt: updatedAt,
                customerName: customerName,
                customerPhone: customerPhone,
                customerId: customerId,
                footerNote: footerNote,
                itemsJson: itemsJson,
                paymentsJson: paymentsJson,
                commandId: commandId,
                syncStatus: syncStatus,
                backendReceiptId: backendReceiptId,
                backendSaleId: backendSaleId,
                lastSyncError: lastSyncError,
                lastSyncedAt: lastSyncedAt,
                tombstone: tombstone,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SalesEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$BusinessHubDatabase,
      $SalesEntriesTable,
      SalesEntry,
      $$SalesEntriesTableFilterComposer,
      $$SalesEntriesTableOrderingComposer,
      $$SalesEntriesTableAnnotationComposer,
      $$SalesEntriesTableCreateCompanionBuilder,
      $$SalesEntriesTableUpdateCompanionBuilder,
      (
        SalesEntry,
        BaseReferences<_$BusinessHubDatabase, $SalesEntriesTable, SalesEntry>,
      ),
      SalesEntry,
      PrefetchHooks Function()
    >;
typedef $$CustomerEntriesTableCreateCompanionBuilder =
    CustomerEntriesCompanion Function({
      required String id,
      required String name,
      Value<String?> phone,
      Value<String?> email,
      Value<String?> notes,
      Value<String> status,
      Value<double> totalSpent,
      Value<double> balance,
      required int createdAt,
      Value<int> updatedAt,
      Value<int?> lastSeenAt,
      Value<int?> lastRemindedAt,
      Value<bool> tombstone,
      Value<int> rowid,
    });
typedef $$CustomerEntriesTableUpdateCompanionBuilder =
    CustomerEntriesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String?> phone,
      Value<String?> email,
      Value<String?> notes,
      Value<String> status,
      Value<double> totalSpent,
      Value<double> balance,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int?> lastSeenAt,
      Value<int?> lastRemindedAt,
      Value<bool> tombstone,
      Value<int> rowid,
    });

class $$CustomerEntriesTableFilterComposer
    extends Composer<_$BusinessHubDatabase, $CustomerEntriesTable> {
  $$CustomerEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get totalSpent => $composableBuilder(
    column: $table.totalSpent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get balance => $composableBuilder(
    column: $table.balance,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastRemindedAt => $composableBuilder(
    column: $table.lastRemindedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get tombstone => $composableBuilder(
    column: $table.tombstone,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CustomerEntriesTableOrderingComposer
    extends Composer<_$BusinessHubDatabase, $CustomerEntriesTable> {
  $$CustomerEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get totalSpent => $composableBuilder(
    column: $table.totalSpent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get balance => $composableBuilder(
    column: $table.balance,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastRemindedAt => $composableBuilder(
    column: $table.lastRemindedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get tombstone => $composableBuilder(
    column: $table.tombstone,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CustomerEntriesTableAnnotationComposer
    extends Composer<_$BusinessHubDatabase, $CustomerEntriesTable> {
  $$CustomerEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<double> get totalSpent => $composableBuilder(
    column: $table.totalSpent,
    builder: (column) => column,
  );

  GeneratedColumn<double> get balance =>
      $composableBuilder(column: $table.balance, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastRemindedAt => $composableBuilder(
    column: $table.lastRemindedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get tombstone =>
      $composableBuilder(column: $table.tombstone, builder: (column) => column);
}

class $$CustomerEntriesTableTableManager
    extends
        RootTableManager<
          _$BusinessHubDatabase,
          $CustomerEntriesTable,
          CustomerEntry,
          $$CustomerEntriesTableFilterComposer,
          $$CustomerEntriesTableOrderingComposer,
          $$CustomerEntriesTableAnnotationComposer,
          $$CustomerEntriesTableCreateCompanionBuilder,
          $$CustomerEntriesTableUpdateCompanionBuilder,
          (
            CustomerEntry,
            BaseReferences<
              _$BusinessHubDatabase,
              $CustomerEntriesTable,
              CustomerEntry
            >,
          ),
          CustomerEntry,
          PrefetchHooks Function()
        > {
  $$CustomerEntriesTableTableManager(
    _$BusinessHubDatabase db,
    $CustomerEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CustomerEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CustomerEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CustomerEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> phone = const Value.absent(),
                Value<String?> email = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<double> totalSpent = const Value.absent(),
                Value<double> balance = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> lastSeenAt = const Value.absent(),
                Value<int?> lastRemindedAt = const Value.absent(),
                Value<bool> tombstone = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CustomerEntriesCompanion(
                id: id,
                name: name,
                phone: phone,
                email: email,
                notes: notes,
                status: status,
                totalSpent: totalSpent,
                balance: balance,
                createdAt: createdAt,
                updatedAt: updatedAt,
                lastSeenAt: lastSeenAt,
                lastRemindedAt: lastRemindedAt,
                tombstone: tombstone,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String?> phone = const Value.absent(),
                Value<String?> email = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<double> totalSpent = const Value.absent(),
                Value<double> balance = const Value.absent(),
                required int createdAt,
                Value<int> updatedAt = const Value.absent(),
                Value<int?> lastSeenAt = const Value.absent(),
                Value<int?> lastRemindedAt = const Value.absent(),
                Value<bool> tombstone = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CustomerEntriesCompanion.insert(
                id: id,
                name: name,
                phone: phone,
                email: email,
                notes: notes,
                status: status,
                totalSpent: totalSpent,
                balance: balance,
                createdAt: createdAt,
                updatedAt: updatedAt,
                lastSeenAt: lastSeenAt,
                lastRemindedAt: lastRemindedAt,
                tombstone: tombstone,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CustomerEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$BusinessHubDatabase,
      $CustomerEntriesTable,
      CustomerEntry,
      $$CustomerEntriesTableFilterComposer,
      $$CustomerEntriesTableOrderingComposer,
      $$CustomerEntriesTableAnnotationComposer,
      $$CustomerEntriesTableCreateCompanionBuilder,
      $$CustomerEntriesTableUpdateCompanionBuilder,
      (
        CustomerEntry,
        BaseReferences<
          _$BusinessHubDatabase,
          $CustomerEntriesTable,
          CustomerEntry
        >,
      ),
      CustomerEntry,
      PrefetchHooks Function()
    >;
typedef $$CommerceOutboxEntriesTableCreateCompanionBuilder =
    CommerceOutboxEntriesCompanion Function({
      required String commandId,
      required String shopId,
      required String commandType,
      required String domain,
      Value<int> baseDomainEpoch,
      required String payloadJson,
      Value<String> syncStatus,
      Value<int> attemptCount,
      Value<String?> lastError,
      required int createdAt,
      Value<int> updatedAt,
      Value<int?> lastAttemptAt,
      Value<int?> completedAt,
      Value<bool> isDeadLetter,
      Value<String?> deadLetterReason,
      Value<int> rowid,
    });
typedef $$CommerceOutboxEntriesTableUpdateCompanionBuilder =
    CommerceOutboxEntriesCompanion Function({
      Value<String> commandId,
      Value<String> shopId,
      Value<String> commandType,
      Value<String> domain,
      Value<int> baseDomainEpoch,
      Value<String> payloadJson,
      Value<String> syncStatus,
      Value<int> attemptCount,
      Value<String?> lastError,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int?> lastAttemptAt,
      Value<int?> completedAt,
      Value<bool> isDeadLetter,
      Value<String?> deadLetterReason,
      Value<int> rowid,
    });

class $$CommerceOutboxEntriesTableFilterComposer
    extends Composer<_$BusinessHubDatabase, $CommerceOutboxEntriesTable> {
  $$CommerceOutboxEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get commandId => $composableBuilder(
    column: $table.commandId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get shopId => $composableBuilder(
    column: $table.shopId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get commandType => $composableBuilder(
    column: $table.commandType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get domain => $composableBuilder(
    column: $table.domain,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get baseDomainEpoch => $composableBuilder(
    column: $table.baseDomainEpoch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDeadLetter => $composableBuilder(
    column: $table.isDeadLetter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deadLetterReason => $composableBuilder(
    column: $table.deadLetterReason,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CommerceOutboxEntriesTableOrderingComposer
    extends Composer<_$BusinessHubDatabase, $CommerceOutboxEntriesTable> {
  $$CommerceOutboxEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get commandId => $composableBuilder(
    column: $table.commandId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get shopId => $composableBuilder(
    column: $table.shopId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get commandType => $composableBuilder(
    column: $table.commandType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get domain => $composableBuilder(
    column: $table.domain,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get baseDomainEpoch => $composableBuilder(
    column: $table.baseDomainEpoch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDeadLetter => $composableBuilder(
    column: $table.isDeadLetter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deadLetterReason => $composableBuilder(
    column: $table.deadLetterReason,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CommerceOutboxEntriesTableAnnotationComposer
    extends Composer<_$BusinessHubDatabase, $CommerceOutboxEntriesTable> {
  $$CommerceOutboxEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get commandId =>
      $composableBuilder(column: $table.commandId, builder: (column) => column);

  GeneratedColumn<String> get shopId =>
      $composableBuilder(column: $table.shopId, builder: (column) => column);

  GeneratedColumn<String> get commandType => $composableBuilder(
    column: $table.commandType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get domain =>
      $composableBuilder(column: $table.domain, builder: (column) => column);

  GeneratedColumn<int> get baseDomainEpoch => $composableBuilder(
    column: $table.baseDomainEpoch,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isDeadLetter => $composableBuilder(
    column: $table.isDeadLetter,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deadLetterReason => $composableBuilder(
    column: $table.deadLetterReason,
    builder: (column) => column,
  );
}

class $$CommerceOutboxEntriesTableTableManager
    extends
        RootTableManager<
          _$BusinessHubDatabase,
          $CommerceOutboxEntriesTable,
          CommerceOutboxEntry,
          $$CommerceOutboxEntriesTableFilterComposer,
          $$CommerceOutboxEntriesTableOrderingComposer,
          $$CommerceOutboxEntriesTableAnnotationComposer,
          $$CommerceOutboxEntriesTableCreateCompanionBuilder,
          $$CommerceOutboxEntriesTableUpdateCompanionBuilder,
          (
            CommerceOutboxEntry,
            BaseReferences<
              _$BusinessHubDatabase,
              $CommerceOutboxEntriesTable,
              CommerceOutboxEntry
            >,
          ),
          CommerceOutboxEntry,
          PrefetchHooks Function()
        > {
  $$CommerceOutboxEntriesTableTableManager(
    _$BusinessHubDatabase db,
    $CommerceOutboxEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CommerceOutboxEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$CommerceOutboxEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CommerceOutboxEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> commandId = const Value.absent(),
                Value<String> shopId = const Value.absent(),
                Value<String> commandType = const Value.absent(),
                Value<String> domain = const Value.absent(),
                Value<int> baseDomainEpoch = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> lastAttemptAt = const Value.absent(),
                Value<int?> completedAt = const Value.absent(),
                Value<bool> isDeadLetter = const Value.absent(),
                Value<String?> deadLetterReason = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CommerceOutboxEntriesCompanion(
                commandId: commandId,
                shopId: shopId,
                commandType: commandType,
                domain: domain,
                baseDomainEpoch: baseDomainEpoch,
                payloadJson: payloadJson,
                syncStatus: syncStatus,
                attemptCount: attemptCount,
                lastError: lastError,
                createdAt: createdAt,
                updatedAt: updatedAt,
                lastAttemptAt: lastAttemptAt,
                completedAt: completedAt,
                isDeadLetter: isDeadLetter,
                deadLetterReason: deadLetterReason,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String commandId,
                required String shopId,
                required String commandType,
                required String domain,
                Value<int> baseDomainEpoch = const Value.absent(),
                required String payloadJson,
                Value<String> syncStatus = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                required int createdAt,
                Value<int> updatedAt = const Value.absent(),
                Value<int?> lastAttemptAt = const Value.absent(),
                Value<int?> completedAt = const Value.absent(),
                Value<bool> isDeadLetter = const Value.absent(),
                Value<String?> deadLetterReason = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CommerceOutboxEntriesCompanion.insert(
                commandId: commandId,
                shopId: shopId,
                commandType: commandType,
                domain: domain,
                baseDomainEpoch: baseDomainEpoch,
                payloadJson: payloadJson,
                syncStatus: syncStatus,
                attemptCount: attemptCount,
                lastError: lastError,
                createdAt: createdAt,
                updatedAt: updatedAt,
                lastAttemptAt: lastAttemptAt,
                completedAt: completedAt,
                isDeadLetter: isDeadLetter,
                deadLetterReason: deadLetterReason,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CommerceOutboxEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$BusinessHubDatabase,
      $CommerceOutboxEntriesTable,
      CommerceOutboxEntry,
      $$CommerceOutboxEntriesTableFilterComposer,
      $$CommerceOutboxEntriesTableOrderingComposer,
      $$CommerceOutboxEntriesTableAnnotationComposer,
      $$CommerceOutboxEntriesTableCreateCompanionBuilder,
      $$CommerceOutboxEntriesTableUpdateCompanionBuilder,
      (
        CommerceOutboxEntry,
        BaseReferences<
          _$BusinessHubDatabase,
          $CommerceOutboxEntriesTable,
          CommerceOutboxEntry
        >,
      ),
      CommerceOutboxEntry,
      PrefetchHooks Function()
    >;
typedef $$ExpenseEntriesTableCreateCompanionBuilder =
    ExpenseEntriesCompanion Function({
      required String id,
      Value<String> category,
      Value<double> amount,
      Value<String> description,
      Value<String> paymentMethod,
      Value<String> paymentReference,
      required String expenseDate,
      Value<String?> actorName,
      required int createdAt,
      Value<int> updatedAt,
      Value<bool> tombstone,
      Value<int> rowid,
    });
typedef $$ExpenseEntriesTableUpdateCompanionBuilder =
    ExpenseEntriesCompanion Function({
      Value<String> id,
      Value<String> category,
      Value<double> amount,
      Value<String> description,
      Value<String> paymentMethod,
      Value<String> paymentReference,
      Value<String> expenseDate,
      Value<String?> actorName,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<bool> tombstone,
      Value<int> rowid,
    });

class $$ExpenseEntriesTableFilterComposer
    extends Composer<_$BusinessHubDatabase, $ExpenseEntriesTable> {
  $$ExpenseEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get paymentMethod => $composableBuilder(
    column: $table.paymentMethod,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get paymentReference => $composableBuilder(
    column: $table.paymentReference,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get expenseDate => $composableBuilder(
    column: $table.expenseDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get actorName => $composableBuilder(
    column: $table.actorName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get tombstone => $composableBuilder(
    column: $table.tombstone,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ExpenseEntriesTableOrderingComposer
    extends Composer<_$BusinessHubDatabase, $ExpenseEntriesTable> {
  $$ExpenseEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paymentMethod => $composableBuilder(
    column: $table.paymentMethod,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paymentReference => $composableBuilder(
    column: $table.paymentReference,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get expenseDate => $composableBuilder(
    column: $table.expenseDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get actorName => $composableBuilder(
    column: $table.actorName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get tombstone => $composableBuilder(
    column: $table.tombstone,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ExpenseEntriesTableAnnotationComposer
    extends Composer<_$BusinessHubDatabase, $ExpenseEntriesTable> {
  $$ExpenseEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<double> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get paymentMethod => $composableBuilder(
    column: $table.paymentMethod,
    builder: (column) => column,
  );

  GeneratedColumn<String> get paymentReference => $composableBuilder(
    column: $table.paymentReference,
    builder: (column) => column,
  );

  GeneratedColumn<String> get expenseDate => $composableBuilder(
    column: $table.expenseDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get actorName =>
      $composableBuilder(column: $table.actorName, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get tombstone =>
      $composableBuilder(column: $table.tombstone, builder: (column) => column);
}

class $$ExpenseEntriesTableTableManager
    extends
        RootTableManager<
          _$BusinessHubDatabase,
          $ExpenseEntriesTable,
          ExpenseEntry,
          $$ExpenseEntriesTableFilterComposer,
          $$ExpenseEntriesTableOrderingComposer,
          $$ExpenseEntriesTableAnnotationComposer,
          $$ExpenseEntriesTableCreateCompanionBuilder,
          $$ExpenseEntriesTableUpdateCompanionBuilder,
          (
            ExpenseEntry,
            BaseReferences<
              _$BusinessHubDatabase,
              $ExpenseEntriesTable,
              ExpenseEntry
            >,
          ),
          ExpenseEntry,
          PrefetchHooks Function()
        > {
  $$ExpenseEntriesTableTableManager(
    _$BusinessHubDatabase db,
    $ExpenseEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExpenseEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExpenseEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExpenseEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<double> amount = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String> paymentMethod = const Value.absent(),
                Value<String> paymentReference = const Value.absent(),
                Value<String> expenseDate = const Value.absent(),
                Value<String?> actorName = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<bool> tombstone = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExpenseEntriesCompanion(
                id: id,
                category: category,
                amount: amount,
                description: description,
                paymentMethod: paymentMethod,
                paymentReference: paymentReference,
                expenseDate: expenseDate,
                actorName: actorName,
                createdAt: createdAt,
                updatedAt: updatedAt,
                tombstone: tombstone,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> category = const Value.absent(),
                Value<double> amount = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String> paymentMethod = const Value.absent(),
                Value<String> paymentReference = const Value.absent(),
                required String expenseDate,
                Value<String?> actorName = const Value.absent(),
                required int createdAt,
                Value<int> updatedAt = const Value.absent(),
                Value<bool> tombstone = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExpenseEntriesCompanion.insert(
                id: id,
                category: category,
                amount: amount,
                description: description,
                paymentMethod: paymentMethod,
                paymentReference: paymentReference,
                expenseDate: expenseDate,
                actorName: actorName,
                createdAt: createdAt,
                updatedAt: updatedAt,
                tombstone: tombstone,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ExpenseEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$BusinessHubDatabase,
      $ExpenseEntriesTable,
      ExpenseEntry,
      $$ExpenseEntriesTableFilterComposer,
      $$ExpenseEntriesTableOrderingComposer,
      $$ExpenseEntriesTableAnnotationComposer,
      $$ExpenseEntriesTableCreateCompanionBuilder,
      $$ExpenseEntriesTableUpdateCompanionBuilder,
      (
        ExpenseEntry,
        BaseReferences<
          _$BusinessHubDatabase,
          $ExpenseEntriesTable,
          ExpenseEntry
        >,
      ),
      ExpenseEntry,
      PrefetchHooks Function()
    >;
typedef $$PurchaseEntriesTableCreateCompanionBuilder =
    PurchaseEntriesCompanion Function({
      required String id,
      required String supplierName,
      Value<String> supplierPhone,
      Value<String> reference,
      Value<double> total,
      Value<double> amountPaid,
      Value<String> paymentMethod,
      Value<String> notes,
      required String purchaseDate,
      Value<String?> actorName,
      required int createdAt,
      Value<int> updatedAt,
      Value<bool> tombstone,
      Value<int> rowid,
    });
typedef $$PurchaseEntriesTableUpdateCompanionBuilder =
    PurchaseEntriesCompanion Function({
      Value<String> id,
      Value<String> supplierName,
      Value<String> supplierPhone,
      Value<String> reference,
      Value<double> total,
      Value<double> amountPaid,
      Value<String> paymentMethod,
      Value<String> notes,
      Value<String> purchaseDate,
      Value<String?> actorName,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<bool> tombstone,
      Value<int> rowid,
    });

class $$PurchaseEntriesTableFilterComposer
    extends Composer<_$BusinessHubDatabase, $PurchaseEntriesTable> {
  $$PurchaseEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get supplierName => $composableBuilder(
    column: $table.supplierName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get supplierPhone => $composableBuilder(
    column: $table.supplierPhone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reference => $composableBuilder(
    column: $table.reference,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get total => $composableBuilder(
    column: $table.total,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get amountPaid => $composableBuilder(
    column: $table.amountPaid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get paymentMethod => $composableBuilder(
    column: $table.paymentMethod,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get purchaseDate => $composableBuilder(
    column: $table.purchaseDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get actorName => $composableBuilder(
    column: $table.actorName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get tombstone => $composableBuilder(
    column: $table.tombstone,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PurchaseEntriesTableOrderingComposer
    extends Composer<_$BusinessHubDatabase, $PurchaseEntriesTable> {
  $$PurchaseEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get supplierName => $composableBuilder(
    column: $table.supplierName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get supplierPhone => $composableBuilder(
    column: $table.supplierPhone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reference => $composableBuilder(
    column: $table.reference,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get total => $composableBuilder(
    column: $table.total,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get amountPaid => $composableBuilder(
    column: $table.amountPaid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paymentMethod => $composableBuilder(
    column: $table.paymentMethod,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get purchaseDate => $composableBuilder(
    column: $table.purchaseDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get actorName => $composableBuilder(
    column: $table.actorName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get tombstone => $composableBuilder(
    column: $table.tombstone,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PurchaseEntriesTableAnnotationComposer
    extends Composer<_$BusinessHubDatabase, $PurchaseEntriesTable> {
  $$PurchaseEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get supplierName => $composableBuilder(
    column: $table.supplierName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get supplierPhone => $composableBuilder(
    column: $table.supplierPhone,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reference =>
      $composableBuilder(column: $table.reference, builder: (column) => column);

  GeneratedColumn<double> get total =>
      $composableBuilder(column: $table.total, builder: (column) => column);

  GeneratedColumn<double> get amountPaid => $composableBuilder(
    column: $table.amountPaid,
    builder: (column) => column,
  );

  GeneratedColumn<String> get paymentMethod => $composableBuilder(
    column: $table.paymentMethod,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get purchaseDate => $composableBuilder(
    column: $table.purchaseDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get actorName =>
      $composableBuilder(column: $table.actorName, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get tombstone =>
      $composableBuilder(column: $table.tombstone, builder: (column) => column);
}

class $$PurchaseEntriesTableTableManager
    extends
        RootTableManager<
          _$BusinessHubDatabase,
          $PurchaseEntriesTable,
          PurchaseEntry,
          $$PurchaseEntriesTableFilterComposer,
          $$PurchaseEntriesTableOrderingComposer,
          $$PurchaseEntriesTableAnnotationComposer,
          $$PurchaseEntriesTableCreateCompanionBuilder,
          $$PurchaseEntriesTableUpdateCompanionBuilder,
          (
            PurchaseEntry,
            BaseReferences<
              _$BusinessHubDatabase,
              $PurchaseEntriesTable,
              PurchaseEntry
            >,
          ),
          PurchaseEntry,
          PrefetchHooks Function()
        > {
  $$PurchaseEntriesTableTableManager(
    _$BusinessHubDatabase db,
    $PurchaseEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PurchaseEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PurchaseEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PurchaseEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> supplierName = const Value.absent(),
                Value<String> supplierPhone = const Value.absent(),
                Value<String> reference = const Value.absent(),
                Value<double> total = const Value.absent(),
                Value<double> amountPaid = const Value.absent(),
                Value<String> paymentMethod = const Value.absent(),
                Value<String> notes = const Value.absent(),
                Value<String> purchaseDate = const Value.absent(),
                Value<String?> actorName = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<bool> tombstone = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PurchaseEntriesCompanion(
                id: id,
                supplierName: supplierName,
                supplierPhone: supplierPhone,
                reference: reference,
                total: total,
                amountPaid: amountPaid,
                paymentMethod: paymentMethod,
                notes: notes,
                purchaseDate: purchaseDate,
                actorName: actorName,
                createdAt: createdAt,
                updatedAt: updatedAt,
                tombstone: tombstone,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String supplierName,
                Value<String> supplierPhone = const Value.absent(),
                Value<String> reference = const Value.absent(),
                Value<double> total = const Value.absent(),
                Value<double> amountPaid = const Value.absent(),
                Value<String> paymentMethod = const Value.absent(),
                Value<String> notes = const Value.absent(),
                required String purchaseDate,
                Value<String?> actorName = const Value.absent(),
                required int createdAt,
                Value<int> updatedAt = const Value.absent(),
                Value<bool> tombstone = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PurchaseEntriesCompanion.insert(
                id: id,
                supplierName: supplierName,
                supplierPhone: supplierPhone,
                reference: reference,
                total: total,
                amountPaid: amountPaid,
                paymentMethod: paymentMethod,
                notes: notes,
                purchaseDate: purchaseDate,
                actorName: actorName,
                createdAt: createdAt,
                updatedAt: updatedAt,
                tombstone: tombstone,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PurchaseEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$BusinessHubDatabase,
      $PurchaseEntriesTable,
      PurchaseEntry,
      $$PurchaseEntriesTableFilterComposer,
      $$PurchaseEntriesTableOrderingComposer,
      $$PurchaseEntriesTableAnnotationComposer,
      $$PurchaseEntriesTableCreateCompanionBuilder,
      $$PurchaseEntriesTableUpdateCompanionBuilder,
      (
        PurchaseEntry,
        BaseReferences<
          _$BusinessHubDatabase,
          $PurchaseEntriesTable,
          PurchaseEntry
        >,
      ),
      PurchaseEntry,
      PrefetchHooks Function()
    >;
typedef $$StockMovementEntriesTableCreateCompanionBuilder =
    StockMovementEntriesCompanion Function({
      required String id,
      required String itemId,
      required String itemName,
      required double delta,
      Value<double?> balanceAfter,
      required String reason,
      Value<String?> refId,
      Value<String> note,
      Value<String?> actorName,
      required int createdAt,
      Value<int> rowid,
    });
typedef $$StockMovementEntriesTableUpdateCompanionBuilder =
    StockMovementEntriesCompanion Function({
      Value<String> id,
      Value<String> itemId,
      Value<String> itemName,
      Value<double> delta,
      Value<double?> balanceAfter,
      Value<String> reason,
      Value<String?> refId,
      Value<String> note,
      Value<String?> actorName,
      Value<int> createdAt,
      Value<int> rowid,
    });

class $$StockMovementEntriesTableFilterComposer
    extends Composer<_$BusinessHubDatabase, $StockMovementEntriesTable> {
  $$StockMovementEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get itemName => $composableBuilder(
    column: $table.itemName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get delta => $composableBuilder(
    column: $table.delta,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get balanceAfter => $composableBuilder(
    column: $table.balanceAfter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get refId => $composableBuilder(
    column: $table.refId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get actorName => $composableBuilder(
    column: $table.actorName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StockMovementEntriesTableOrderingComposer
    extends Composer<_$BusinessHubDatabase, $StockMovementEntriesTable> {
  $$StockMovementEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get itemName => $composableBuilder(
    column: $table.itemName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get delta => $composableBuilder(
    column: $table.delta,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get balanceAfter => $composableBuilder(
    column: $table.balanceAfter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get refId => $composableBuilder(
    column: $table.refId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get actorName => $composableBuilder(
    column: $table.actorName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StockMovementEntriesTableAnnotationComposer
    extends Composer<_$BusinessHubDatabase, $StockMovementEntriesTable> {
  $$StockMovementEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get itemId =>
      $composableBuilder(column: $table.itemId, builder: (column) => column);

  GeneratedColumn<String> get itemName =>
      $composableBuilder(column: $table.itemName, builder: (column) => column);

  GeneratedColumn<double> get delta =>
      $composableBuilder(column: $table.delta, builder: (column) => column);

  GeneratedColumn<double> get balanceAfter => $composableBuilder(
    column: $table.balanceAfter,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<String> get refId =>
      $composableBuilder(column: $table.refId, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get actorName =>
      $composableBuilder(column: $table.actorName, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$StockMovementEntriesTableTableManager
    extends
        RootTableManager<
          _$BusinessHubDatabase,
          $StockMovementEntriesTable,
          StockMovementEntry,
          $$StockMovementEntriesTableFilterComposer,
          $$StockMovementEntriesTableOrderingComposer,
          $$StockMovementEntriesTableAnnotationComposer,
          $$StockMovementEntriesTableCreateCompanionBuilder,
          $$StockMovementEntriesTableUpdateCompanionBuilder,
          (
            StockMovementEntry,
            BaseReferences<
              _$BusinessHubDatabase,
              $StockMovementEntriesTable,
              StockMovementEntry
            >,
          ),
          StockMovementEntry,
          PrefetchHooks Function()
        > {
  $$StockMovementEntriesTableTableManager(
    _$BusinessHubDatabase db,
    $StockMovementEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StockMovementEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StockMovementEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$StockMovementEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> itemId = const Value.absent(),
                Value<String> itemName = const Value.absent(),
                Value<double> delta = const Value.absent(),
                Value<double?> balanceAfter = const Value.absent(),
                Value<String> reason = const Value.absent(),
                Value<String?> refId = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<String?> actorName = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StockMovementEntriesCompanion(
                id: id,
                itemId: itemId,
                itemName: itemName,
                delta: delta,
                balanceAfter: balanceAfter,
                reason: reason,
                refId: refId,
                note: note,
                actorName: actorName,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String itemId,
                required String itemName,
                required double delta,
                Value<double?> balanceAfter = const Value.absent(),
                required String reason,
                Value<String?> refId = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<String?> actorName = const Value.absent(),
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => StockMovementEntriesCompanion.insert(
                id: id,
                itemId: itemId,
                itemName: itemName,
                delta: delta,
                balanceAfter: balanceAfter,
                reason: reason,
                refId: refId,
                note: note,
                actorName: actorName,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StockMovementEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$BusinessHubDatabase,
      $StockMovementEntriesTable,
      StockMovementEntry,
      $$StockMovementEntriesTableFilterComposer,
      $$StockMovementEntriesTableOrderingComposer,
      $$StockMovementEntriesTableAnnotationComposer,
      $$StockMovementEntriesTableCreateCompanionBuilder,
      $$StockMovementEntriesTableUpdateCompanionBuilder,
      (
        StockMovementEntry,
        BaseReferences<
          _$BusinessHubDatabase,
          $StockMovementEntriesTable,
          StockMovementEntry
        >,
      ),
      StockMovementEntry,
      PrefetchHooks Function()
    >;
typedef $$CustomerLedgerEntriesTableCreateCompanionBuilder =
    CustomerLedgerEntriesCompanion Function({
      required String id,
      required String customerId,
      required String type,
      required double amount,
      required double balanceAfter,
      Value<String?> refId,
      Value<String> note,
      Value<String?> actorName,
      required int createdAt,
      Value<int> rowid,
    });
typedef $$CustomerLedgerEntriesTableUpdateCompanionBuilder =
    CustomerLedgerEntriesCompanion Function({
      Value<String> id,
      Value<String> customerId,
      Value<String> type,
      Value<double> amount,
      Value<double> balanceAfter,
      Value<String?> refId,
      Value<String> note,
      Value<String?> actorName,
      Value<int> createdAt,
      Value<int> rowid,
    });

class $$CustomerLedgerEntriesTableFilterComposer
    extends Composer<_$BusinessHubDatabase, $CustomerLedgerEntriesTable> {
  $$CustomerLedgerEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customerId => $composableBuilder(
    column: $table.customerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get balanceAfter => $composableBuilder(
    column: $table.balanceAfter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get refId => $composableBuilder(
    column: $table.refId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get actorName => $composableBuilder(
    column: $table.actorName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CustomerLedgerEntriesTableOrderingComposer
    extends Composer<_$BusinessHubDatabase, $CustomerLedgerEntriesTable> {
  $$CustomerLedgerEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customerId => $composableBuilder(
    column: $table.customerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get balanceAfter => $composableBuilder(
    column: $table.balanceAfter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get refId => $composableBuilder(
    column: $table.refId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get actorName => $composableBuilder(
    column: $table.actorName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CustomerLedgerEntriesTableAnnotationComposer
    extends Composer<_$BusinessHubDatabase, $CustomerLedgerEntriesTable> {
  $$CustomerLedgerEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get customerId => $composableBuilder(
    column: $table.customerId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<double> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<double> get balanceAfter => $composableBuilder(
    column: $table.balanceAfter,
    builder: (column) => column,
  );

  GeneratedColumn<String> get refId =>
      $composableBuilder(column: $table.refId, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get actorName =>
      $composableBuilder(column: $table.actorName, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$CustomerLedgerEntriesTableTableManager
    extends
        RootTableManager<
          _$BusinessHubDatabase,
          $CustomerLedgerEntriesTable,
          CustomerLedgerEntry,
          $$CustomerLedgerEntriesTableFilterComposer,
          $$CustomerLedgerEntriesTableOrderingComposer,
          $$CustomerLedgerEntriesTableAnnotationComposer,
          $$CustomerLedgerEntriesTableCreateCompanionBuilder,
          $$CustomerLedgerEntriesTableUpdateCompanionBuilder,
          (
            CustomerLedgerEntry,
            BaseReferences<
              _$BusinessHubDatabase,
              $CustomerLedgerEntriesTable,
              CustomerLedgerEntry
            >,
          ),
          CustomerLedgerEntry,
          PrefetchHooks Function()
        > {
  $$CustomerLedgerEntriesTableTableManager(
    _$BusinessHubDatabase db,
    $CustomerLedgerEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CustomerLedgerEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$CustomerLedgerEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CustomerLedgerEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> customerId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<double> amount = const Value.absent(),
                Value<double> balanceAfter = const Value.absent(),
                Value<String?> refId = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<String?> actorName = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CustomerLedgerEntriesCompanion(
                id: id,
                customerId: customerId,
                type: type,
                amount: amount,
                balanceAfter: balanceAfter,
                refId: refId,
                note: note,
                actorName: actorName,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String customerId,
                required String type,
                required double amount,
                required double balanceAfter,
                Value<String?> refId = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<String?> actorName = const Value.absent(),
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => CustomerLedgerEntriesCompanion.insert(
                id: id,
                customerId: customerId,
                type: type,
                amount: amount,
                balanceAfter: balanceAfter,
                refId: refId,
                note: note,
                actorName: actorName,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CustomerLedgerEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$BusinessHubDatabase,
      $CustomerLedgerEntriesTable,
      CustomerLedgerEntry,
      $$CustomerLedgerEntriesTableFilterComposer,
      $$CustomerLedgerEntriesTableOrderingComposer,
      $$CustomerLedgerEntriesTableAnnotationComposer,
      $$CustomerLedgerEntriesTableCreateCompanionBuilder,
      $$CustomerLedgerEntriesTableUpdateCompanionBuilder,
      (
        CustomerLedgerEntry,
        BaseReferences<
          _$BusinessHubDatabase,
          $CustomerLedgerEntriesTable,
          CustomerLedgerEntry
        >,
      ),
      CustomerLedgerEntry,
      PrefetchHooks Function()
    >;

class $BusinessHubDatabaseManager {
  final _$BusinessHubDatabase _db;
  $BusinessHubDatabaseManager(this._db);
  $$ShopSettingsEntriesTableTableManager get shopSettingsEntries =>
      $$ShopSettingsEntriesTableTableManager(_db, _db.shopSettingsEntries);
  $$InventoryEntriesTableTableManager get inventoryEntries =>
      $$InventoryEntriesTableTableManager(_db, _db.inventoryEntries);
  $$InventoryPrivateEntriesTableTableManager get inventoryPrivateEntries =>
      $$InventoryPrivateEntriesTableTableManager(
        _db,
        _db.inventoryPrivateEntries,
      );
  $$SalesEntriesTableTableManager get salesEntries =>
      $$SalesEntriesTableTableManager(_db, _db.salesEntries);
  $$CustomerEntriesTableTableManager get customerEntries =>
      $$CustomerEntriesTableTableManager(_db, _db.customerEntries);
  $$CommerceOutboxEntriesTableTableManager get commerceOutboxEntries =>
      $$CommerceOutboxEntriesTableTableManager(_db, _db.commerceOutboxEntries);
  $$ExpenseEntriesTableTableManager get expenseEntries =>
      $$ExpenseEntriesTableTableManager(_db, _db.expenseEntries);
  $$PurchaseEntriesTableTableManager get purchaseEntries =>
      $$PurchaseEntriesTableTableManager(_db, _db.purchaseEntries);
  $$StockMovementEntriesTableTableManager get stockMovementEntries =>
      $$StockMovementEntriesTableTableManager(_db, _db.stockMovementEntries);
  $$CustomerLedgerEntriesTableTableManager get customerLedgerEntries =>
      $$CustomerLedgerEntriesTableTableManager(_db, _db.customerLedgerEntries);
}
