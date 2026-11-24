part of '../finance_entry_screen.dart';

extension _FinanceEntryOptions on _FinanceEntryScreenState {
  Future<void> _loadOptions() async {
    try {
      final boundOriginalUuid =
          widget.originalTransaction?.uuid ??
          widget.transaction?.relatedTransactionUuid;
      final options = await Future.wait<dynamic>([
        FinanceStorage.getCategories(includeArchived: true),
        FinanceStorage.getPaymentMethods(includeArchived: true),
        FinanceStorage.getTemplates(),
        _isEditingInstallment
            ? FinanceStorage.getInstallmentGroup(
                widget.transaction!.installmentGroupUuid!,
                includeDeleted: true,
              )
            : Future.value(const <FinanceTransaction>[]),
        widget.originalTransaction != null
            ? Future.value(widget.originalTransaction)
            : boundOriginalUuid == null
            ? Future.value(null)
            : FinanceRepository.getTransaction(boundOriginalUuid),
        boundOriginalUuid == null
            ? Future.value(0)
            : FinanceRepository.getRemainingRefundableMinor(
                boundOriginalUuid,
                excludingRefundUuid: widget.transaction?.uuid,
              ),
        widget.transaction == null
            ? Future.value(null)
            : FinanceStorage.getRepaymentForInterestTransaction(
                widget.transaction!.uuid,
              ),
      ]);
      if (!mounted) return;
      final installmentGroup = options[3] as List<FinanceTransaction>;
      final originalTransaction = options[4] as FinanceTransaction?;
      final remainingRefundableMinor = options[5] as int;
      if (installmentGroup.isNotEmpty) {
        final first = installmentGroup.firstWhere(
          (item) => item.installmentIndex == 1,
          orElse: () => installmentGroup.first,
        );
        final total =
            first.installmentTotalMinor ??
            installmentGroup.fold<int>(
              0,
              (sum, item) => sum + item.amountMinor,
            );
        _existingInstallments = installmentGroup;
        _type = first.type;
        _date = dateFromKey(first.transactionDate);
        _timezoneOffsetMinutes = first.timezoneOffsetMinutes;
        final firstOccurred = first.occurrenceLocalTime;
        _occurredAt =
            firstOccurred != null &&
                dateKey(firstOccurred) == first.transactionDate
            ? firstOccurred
            : null;
        _occurrenceTimeExplicit = _occurredAt != null;
        _amountExpression = null;
        _amountController.text = formatFinanceAmount(total, withSymbol: false);
        _merchantController.text = first.merchant ?? '';
        _noteController.text = first.note ?? '';
        _categoryUuid = first.categoryUuid;
        _paymentMethodUuid = first.paymentMethodUuid;
        _installmentEnabled = true;
        _installmentCount = first.installmentCount ?? installmentGroup.length;
        _installmentCountController.text = _installmentCount.toString();
      }
      _mutateState(() {
        _replaceCategories(options[0] as List<FinanceCategory>);
        _replacePaymentMethods(options[1] as List<FinancePaymentMethod>);
        _templates = options[2] as List<FinanceEntryTemplate>;
        _originalTransaction = originalTransaction;
        _remainingRefundableMinor = remainingRefundableMinor;
        _linkedRepayment = options[6] as FinanceLoanInstallment?;
        if (!_isEditing &&
            originalTransaction != null &&
            _amountController.text.trim().isEmpty &&
            remainingRefundableMinor > 0) {
          _amountExpression = null;
          _amountController.text = formatFinanceAmount(
            remainingRefundableMinor,
            withSymbol: false,
          );
        }
        _isLoading = false;
      });
      _clearArchivedNewEntryAssociations();
      _resolveDraftSelections();
      _normalizeSelections(
        allowDefaultCategory:
            widget.transaction == null &&
            widget.originalTransaction == null &&
            !_archivedCategoryRequiresSelection &&
            !_shouldKeepUnresolvedDraftCategory(),
        preserveUnresolvedCategory:
            widget.transaction != null || widget.originalTransaction != null,
        preserveUnresolvedPaymentMethod:
            widget.transaction != null || widget.originalTransaction != null,
      );
      _drainPendingCatalogRefresh();
    } catch (error) {
      if (!mounted) return;
      _mutateState(() => _isLoading = false);
      _showError('加载分类失败：$error');
      _drainPendingCatalogRefresh();
    }
  }

  void _resolveDraftSelections() {
    final draft = widget.initialDraft;
    if (draft == null || widget.transaction != null) return;
    _resolveSelectionsFromDraft(draft);
  }

  void _resolveSelectionsFromDraft(FinanceEntryDraft draft) {
    final categoryType = financeCategoryTypeForTransaction(_type);
    final hasValidCategoryUuid = _categories.any(
      (item) =>
          item.uuid == _categoryUuid &&
          item.type == categoryType &&
          !item.isArchived &&
          !item.isDeleted,
    );
    if (!hasValidCategoryUuid && draft.categoryName != null) {
      final wanted = _normalizeOptionName(draft.categoryName!);
      final semanticWanted = FinanceTextParser.inferCategoryName(
        draft.categoryName!,
        _type,
      );
      final candidates = _categories
          .where(
            (item) =>
                item.type == categoryType &&
                !item.isArchived &&
                !item.isDeleted,
          )
          .toList();
      final displayMatches = candidates
          .where(
            (item) =>
                _normalizeOptionName(
                  financeCategoryDisplayName(item, _categories),
                ) ==
                wanted,
          )
          .toList();
      final nameMatches = candidates
          .where((item) => _normalizeOptionName(item.name) == wanted)
          .toList();
      final exactMatches = nameMatches.isNotEmpty
          ? nameMatches
          : displayMatches;
      if (exactMatches.length == 1) {
        _categoryUuid = exactMatches.single.uuid;
      } else if (exactMatches.isEmpty && semanticWanted != null) {
        final semanticMatches = candidates
            .where(
              (item) =>
                  FinanceTextParser.inferCategoryName(item.name, _type) ==
                  semanticWanted,
            )
            .toList();
        _categoryUuid = semanticMatches.length == 1
            ? semanticMatches.single.uuid
            : null;
      } else {
        _categoryUuid = null;
      }
    }
    final resolvedCategory = _categories.any(
      (item) =>
          item.uuid == _categoryUuid &&
          item.type == categoryType &&
          !item.isArchived &&
          !item.isDeleted,
    );
    final requestedCategoryUuid = draft.categoryUuid?.trim();
    final requestedCategoryName = draft.categoryName?.trim();
    if (!resolvedCategory &&
        _categories.any((item) {
          if (item.type != categoryType || !item.isArchived || item.isDeleted) {
            return false;
          }
          if (item.uuid == requestedCategoryUuid) return true;
          if (requestedCategoryName == null || requestedCategoryName.isEmpty) {
            return false;
          }
          final wanted = _normalizeOptionName(requestedCategoryName);
          final semanticWanted = FinanceTextParser.inferCategoryName(
            requestedCategoryName,
            _type,
          );
          return _normalizeOptionName(item.name) == wanted ||
              _normalizeOptionName(
                    financeCategoryDisplayName(item, _categories),
                  ) ==
                  wanted ||
              (semanticWanted != null &&
                  FinanceTextParser.inferCategoryName(item.name, _type) ==
                      semanticWanted);
        })) {
      _archivedCategoryRequiresSelection = true;
    }
    final draftPaymentMethodName = draft.paymentMethodName?.trim();
    if (!_paymentMethodSelectionEdited) {
      final hasValidPaymentMethodUuid = _paymentMethods.any(
        (item) =>
            item.uuid == _paymentMethodUuid &&
            !item.isArchived &&
            !item.isDeleted,
      );
      if (!hasValidPaymentMethodUuid) {
        _paymentMethodUuid = null;
        if (draftPaymentMethodName?.isNotEmpty == true) {
          final wanted = _normalizeOptionName(draftPaymentMethodName!);
          final matches = _paymentMethods
              .where((item) => !item.isArchived && !item.isDeleted)
              .where((item) => _normalizeOptionName(item.name) == wanted)
              .toList();
          final matched = matches.length == 1 ? matches.single : null;
          _paymentMethodUuid = matched?.uuid;
          _unmatchedDraftPaymentMethodName = matched == null
              ? draftPaymentMethodName
              : null;
        }
      }
    }
  }

  bool _shouldKeepUnresolvedDraftCategory() {
    final draft = widget.initialDraft;
    if (draft == null || widget.transaction != null) return false;
    final isRecognitionDraft =
        draft.source == FinanceEntrySource.ai ||
        draft.source == FinanceEntrySource.import;
    final requestedUuid = draft.categoryUuid?.trim();
    final requestedName = draft.categoryName?.trim();
    if ((requestedUuid == null || requestedUuid.isEmpty) &&
        (requestedName == null || requestedName.isEmpty)) {
      // Recognition/import drafts must never silently become the first local
      // category (usually 餐饮) just because the model omitted a category.
      return isRecognitionDraft;
    }
    final categoryType = financeCategoryTypeForTransaction(_type);
    final resolved =
        _categoryUuid != null &&
        _categories.any(
          (item) =>
              item.uuid == _categoryUuid &&
              item.type == categoryType &&
              !item.isArchived &&
              !item.isDeleted,
        );
    return !resolved;
  }

  String _normalizeOptionName(String value) {
    return value
        .replaceAll(_optionNameLeadingDecorationPattern, '')
        .replaceAll(_optionNameWhitespacePattern, '')
        .trim()
        .toLowerCase();
  }

  String _categoryName(FinanceCategory category) =>
      _categoryDisplayNameCache.putIfAbsent(
        category.uuid,
        () => financeCategoryDisplayName(category, _categories),
      );

  String _paymentMethodName(FinancePaymentMethod method) =>
      _paymentMethodDisplayNameCache.putIfAbsent(
        method.uuid,
        () => financePaymentMethodDisplayName(method, _visiblePaymentMethods),
      );

  void _replaceCategories(List<FinanceCategory> categories) {
    _categories = categories;
    _categoriesByUuid.clear();
    for (final category in categories) {
      _categoriesByUuid.putIfAbsent(category.uuid, () => category);
    }
    _categoryDisplayNameCache.clear();
  }

  void _replacePaymentMethods(List<FinancePaymentMethod> paymentMethods) {
    _paymentMethods = paymentMethods;
    _paymentMethodsByUuid.clear();
    for (final method in paymentMethods) {
      _paymentMethodsByUuid.putIfAbsent(method.uuid, () => method);
    }
    _paymentMethodDisplayNameCache.clear();
  }

  FinanceCategory? _categoryByUuid(String? uuid) {
    final normalized = uuid?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    return _categoriesByUuid[normalized];
  }

  FinanceCategory _topLevelCategory(FinanceCategory category) {
    var current = category;
    final visited = <String>{category.uuid};
    while (true) {
      final parentUuid = current.parentUuid?.trim();
      if (parentUuid == null ||
          parentUuid.isEmpty ||
          !visited.add(parentUuid)) {
        return current;
      }
      final parent = _categoryByUuid(parentUuid);
      if (parent == null || parent.type != current.type) return current;
      current = parent;
    }
  }

  List<FinanceCategory> get _visibleCategories {
    final type = financeCategoryTypeForTransaction(_type);
    final result = _categories
        .where(
          (item) => item.type == type && !item.isArchived && !item.isDeleted,
        )
        .toList();
    if (_categoryUuid != null &&
        result.every((item) => item.uuid != _categoryUuid)) {
      final selected = _categories.where(
        (item) =>
            item.uuid == _categoryUuid && item.type == type && !item.isDeleted,
      );
      result.insertAll(0, selected);
    }
    return result;
  }

  List<FinanceCategory> get _visibleCategoryParents {
    final type = financeCategoryTypeForTransaction(_type);
    final roots = _categories
        .where(
          (item) =>
              item.type == type &&
              !item.isArchived &&
              !item.isDeleted &&
              (item.parentUuid == null || item.parentUuid!.trim().isEmpty),
        )
        .toList();
    final selected = _categoryByUuid(_categoryUuid);
    final selectedRoot = selected == null ? null : _topLevelCategory(selected);
    if (selectedRoot != null &&
        !selectedRoot.isDeleted &&
        roots.every((item) => item.uuid != selectedRoot.uuid)) {
      roots.insert(0, selectedRoot);
    }
    return roots;
  }

  List<FinanceCategory> _childrenOf(FinanceCategory parent) {
    return _visibleCategories
        .where((item) => item.parentUuid?.trim() == parent.uuid)
        .toList();
  }

  int _nextSubcategorySortOrder(FinanceCategory parent) {
    var maxSortOrder = parent.sortOrder;
    for (final category in _categories) {
      if (category.parentUuid?.trim() == parent.uuid &&
          category.sortOrder > maxSortOrder) {
        maxSortOrder = category.sortOrder;
      }
    }
    return maxSortOrder + 1;
  }

  List<FinancePaymentMethod> get _visiblePaymentMethods {
    final result = _paymentMethods
        .where((item) => !item.isArchived && !item.isDeleted)
        .toList();
    if (_paymentMethodUuid != null &&
        result.every((item) => item.uuid != _paymentMethodUuid)) {
      final selected = _paymentMethods.where(
        (item) => item.uuid == _paymentMethodUuid && !item.isDeleted,
      );
      result.insertAll(0, selected);
    }
    return result;
  }

  void _normalizeSelections({
    bool notify = true,
    bool allowDefaultCategory = true,
    bool preserveUnresolvedCategory = false,
    bool preserveUnresolvedPaymentMethod = false,
  }) {
    final categories = _visibleCategories;
    if (_categoryUuid == null) {
      _categoryUuid = allowDefaultCategory && categories.isNotEmpty
          ? categories.first.uuid
          : null;
    } else if (!preserveUnresolvedCategory &&
        categories.every((item) => item.uuid != _categoryUuid)) {
      _categoryUuid = allowDefaultCategory && categories.isNotEmpty
          ? categories.first.uuid
          : null;
    }
    if (!preserveUnresolvedPaymentMethod &&
        _paymentMethodUuid != null &&
        _visiblePaymentMethods.every(
          (item) => item.uuid != _paymentMethodUuid,
        )) {
      _paymentMethodUuid = null;
    }
    if (notify && mounted) _mutateState(() {});
  }

  void _clearArchivedNewEntryAssociations() {
    if (widget.transaction != null || widget.originalTransaction != null) {
      _archivedCategoryRequiresSelection = false;
      return;
    }

    final category = _categoryByUuid(_categoryUuid);
    _archivedCategoryRequiresSelection = category?.isArchived == true;
    if (_archivedCategoryRequiresSelection) _categoryUuid = null;

    final paymentMethod = _paymentMethods
        .where((item) => item.uuid == _paymentMethodUuid)
        .firstOrNull;
    if (paymentMethod?.isArchived == true) _paymentMethodUuid = null;
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus(
      disposition: UnfocusDisposition.scope,
    );
  }
}
