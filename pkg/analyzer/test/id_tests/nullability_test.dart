// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:_fe_analyzer_shared/src/testing/id.dart' show ActualData, Id;
import 'package:_fe_analyzer_shared/src/testing/id_testing.dart';
import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_system.dart';
import 'package:analyzer/src/dart/analysis/testing_data.dart';
import 'package:analyzer/src/dart/ast/extensions.dart';
import 'package:analyzer/src/dart/resolver/flow_analysis_visitor.dart';
import 'package:analyzer/src/util/ast_data_extractor.dart';
import 'package:test/test.dart';

import '../util/id_testing_helper.dart';

main(List<String> args) async {
  Directory dataDir = Directory.fromUri(Platform.script.resolve(
      '../../../_fe_analyzer_shared/test/flow_analysis/nullability/data'));
  return runTests<String>(dataDir,
      args: args,
      createUriForFileName: createUriForFileName,
      onFailure: onFailure,
      runTest:
          runTestFor(const _NullabilityDataComputer(), [analyzerNnbdConfig]));
}

class FlowTestBase {
  late final FlowAnalysisDataForTesting flowResult;

  /// Resolve the given [code] and track nullability in the unit.
  Future<void> trackCode(String code) async {
    TestResult<String> testResult = await checkTests(code,
        const _NullabilityDataComputer(), FeatureSet.latestLanguageVersion());
    if (testResult.hasFailures) {
      fail('Failure(s)');
    }
  }
}

class _NullabilityDataComputer extends DataComputer<String> {
  const _NullabilityDataComputer();

  @override
  DataInterpreter<String> get dataValidator =>
      const _NullabilityDataInterpreter();

  @override
  void computeUnitData(TestingData testingData, CompilationUnit unit,
      Map<Id, ActualData<String>> actualMap) {
    var unitElement = unit.declaredElement!;
    _NullabilityDataExtractor(
            unitElement.source.uri, actualMap, unitElement.library.typeSystem)
        .run(unit);
  }
}

class _NullabilityDataExtractor extends AstDataExtractor<String> {
  final TypeSystem _typeSystem;

  _NullabilityDataExtractor(
      Uri uri, Map<Id, ActualData<String>> actualMap, this._typeSystem)
      : super(uri, actualMap);

  @override
  String? computeNodeValue(Id id, AstNode node) {
    if (node is SimpleIdentifier &&
        node.inGetterContext() &&
        !node.inDeclarationContext()) {
      var element = node.staticElement;
      if (element is LocalVariableElement || element is ParameterElement) {
        var promotedType = _readType(node);
        var declaredType = (element as VariableElement).type;
        var isPromoted = promotedType != declaredType;
        if (isPromoted &&
            _typeSystem.isPotentiallyNullable(declaredType) &&
            !_typeSystem.isPotentiallyNullable(promotedType)) {
          return 'nonNullable';
        }
      }
    }
    return null;
  }

  static DartType _readType(SimpleIdentifier node) {
    var parent = node.parent;
    if (parent is AssignmentExpression && parent.leftHandSide == node) {
      return parent.readType!;
    } else if (parent is PostfixExpression) {
      return parent.readType ?? node.typeOrThrow;
    } else if (parent is PrefixExpression) {
      return parent.readType ?? node.typeOrThrow;
    } else {
      return node.typeOrThrow;
    }
  }
}

class _NullabilityDataInterpreter implements DataInterpreter<String> {
  const _NullabilityDataInterpreter();

  @override
  String getText(String actualData, [String? indentation]) => actualData;

  @override
  String? isAsExpected(String actualData, String? expectedData) {
    if (actualData == expectedData) {
      return null;
    } else {
      return 'Expected $expectedData, got $actualData';
    }
  }

  @override
  bool isEmpty(String actualData) => actualData.isEmpty;
}
