import importlib.util
import io
import pathlib
import tempfile
import unittest
from contextlib import redirect_stdout

spec = importlib.util.spec_from_file_location('check_swift', pathlib.Path(__file__).with_name('check-swift.py'))
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


class SwiftCopyChecks(unittest.TestCase):
    def test_preview_titles_and_nested_sample_data_are_not_application_copy(self):
        source = '''
Text("CANCEL")
#Preview("中文预览") {
    VStack { Text(verbatim: "示例 { 内容 }") }
    let example = ["name": "哑铃飞鸟"]
}
Text("正式界面")
#Preview { Text(verbatim: "另一个预览") }
'''
        self.assertEqual(list(check.scan(check.without_previews(source))), ['正式界面'])

    def test_preview_marker_in_comments_or_strings_does_not_hide_application_copy(self):
        source = '''
// #Preview { }
/* #Preview { } */
let text = "#Preview { }"
Text("正式界面")
'''
        self.assertEqual(list(check.scan(check.without_previews(source))), ['正式界面'])

    def test_debug_preview_helpers_are_excluded_without_hiding_release_copy(self):
        source = '''
#if DEBUG
#Preview("中文预览") { Text(verbatim: .canvas()) }
private extension String {
    static func canvas() -> String { "哑铃飞鸟" }
}
#else
Text("正式界面")
#endif
#if DEBUG
Text("调试界面")
#endif
'''
        self.assertEqual(list(check.scan(check.without_previews(source))), ['正式界面', '调试界面'])

    def test_private_factory_used_only_by_preview_needs_no_debug_guard(self):
        source = '''
#Preview("训练中") { SampleView(snapshot: .canvas()) }
private extension Snapshot {
    static func canvas() -> Self { Self(name: "哑铃飞鸟") }
    static func applicationDefault() -> Self { Self(name: "正式默认值") }
}
Text("正式界面")
'''
        self.assertEqual(list(check.scan(check.without_previews(source))), ['正式默认值', '正式界面'])

    def test_widget_preview_includes_all_named_trailing_closures(self):
        source = '''
#Preview("锁屏", as: .content, using: Attributes()) {
    Widget()
} contentStates: {
    Snapshot.canvas()
    Snapshot(name: "内联预览样例")
}
private extension Snapshot {
    static func canvas() -> Self { Self(name: "哑铃飞鸟") }
}
Text("正式界面")
'''
        self.assertEqual(list(check.scan(check.without_previews(source))), ['正式界面'])

    def test_preview_arguments_can_contain_closures_before_the_preview_body(self):
        source = '''
#Preview(using: Attributes(makeName: { "参数样例" })) {
    SampleView(snapshot: .canvas())
}
private extension Snapshot {
    static func canvas() -> Self { Self(name: "预览样例") }
}
Text("正式界面")
'''
        self.assertEqual(list(check.scan(check.without_previews(source))), ['正式界面'])

    def test_preview_factory_dependencies_are_excluded_transitively(self):
        source = '''
#Preview { SampleView(snapshot: Snapshot.canvas()) }
private extension Snapshot {
    static func canvas() -> Self { Self(name: sampleName()) }
    static func sampleName() -> String { "预览样例" }
}
'''
        self.assertEqual(list(check.scan(check.without_previews(source))), [])

    def test_private_file_factory_can_be_used_only_by_a_preview(self):
        source = '''
#Preview { SampleView(snapshot: makeSample()) }
private func makeSample() -> Snapshot { Snapshot(name: "预览样例") }
'''
        self.assertEqual(list(check.scan(check.without_previews(source))), [])

    def test_factory_also_used_by_application_code_is_still_checked(self):
        source = '''
#Preview { SampleView(snapshot: .canvas()) }
let liveSnapshot = Snapshot.canvas()
private extension Snapshot {
    static func canvas() -> Self { Self(name: "正式界面也使用的样例") }
}
'''
        self.assertEqual(list(check.scan(check.without_previews(source))), ['正式界面也使用的样例'])

    def test_factory_referenced_as_a_value_is_still_application_code(self):
        source = '''
#Preview { SampleView(snapshot: .canvas()) }
let makeLiveSnapshot = Snapshot.canvas
private extension Snapshot {
    static func canvas() -> Self { Self(name: "正式界面也使用的样例") }
}
'''
        self.assertEqual(list(check.scan(check.without_previews(source))), ['正式界面也使用的样例'])

    def test_factory_used_in_application_string_interpolation_is_still_checked(self):
        source = r'''
#Preview { SampleView(snapshot: .canvas()) }
Text("\(Snapshot.canvas())")
private extension Snapshot {
    static func canvas() -> Self { Self(name: "正式插值也使用的样例") }
}
'''
        self.assertEqual(list(check.scan(check.without_previews(source))), ['正式插值也使用的样例'])

    def test_runtime_references_keep_transitive_factory_dependencies_checked(self):
        source = '''
#Preview { SampleView(snapshot: .canvas()) }
let liveSnapshot = Snapshot.canvas()
private extension Snapshot {
    static func canvas() -> Self { Self(name: sampleName()) }
    static func sampleName() -> String { "正式界面也使用的样例" }
}
'''
        self.assertEqual(list(check.scan(check.without_previews(source))), ['正式界面也使用的样例'])

    def test_shared_dependency_does_not_hide_its_application_copy(self):
        source = '''
#Preview { SampleView(snapshot: .canvas()) }
Text(Snapshot.sampleName())
private extension Snapshot {
    static func canvas() -> Self { Self(name: "预览专用", detail: sampleName()) }
    static func sampleName() -> String { "正式界面也使用的文案" }
}
'''
        self.assertEqual(list(check.scan(check.without_previews(source))), ['正式界面也使用的文案'])

    def test_public_factory_is_not_assumed_to_be_preview_only(self):
        source = '''
#Preview { SampleView(snapshot: .canvas()) }
extension Snapshot {
    static func canvas() -> Self { Self(name: "其他文件可能使用的文案") }
}
'''
        self.assertEqual(list(check.scan(check.without_previews(source))), ['其他文件可能使用的文案'])

    def test_ambiguous_factory_names_are_not_exempted(self):
        source = '''
#Preview { SampleView(snapshot: First.canvas()) }
private extension First {
    static func canvas() -> Self { Self(name: "第一个样例") }
}
private extension Second {
    static func canvas() -> Self { Self(name: "第二个样例") }
}
'''
        self.assertEqual(list(check.scan(check.without_previews(source))), ['第一个样例', '第二个样例'])

    def test_factory_name_in_a_preview_title_is_not_a_factory_reference(self):
        source = '''
#Preview("canvas") { Text("CANCEL") }
private extension Snapshot {
    static func canvas() -> Self { Self(name: "未被预览调用的文案") }
}
'''
        self.assertEqual(list(check.scan(check.without_previews(source))), ['未被预览调用的文案'])

    def test_preview_does_not_exempt_other_code_in_the_same_debug_section(self):
        source = '''
#if DEBUG
#Preview { Text("预览样例") }
Text("调试界面")
#else
Text("正式界面")
#endif
'''
        self.assertEqual(list(check.scan(check.without_previews(source))), ['调试界面', '正式界面'])

    def test_nested_comments_cannot_start_a_fake_preview(self):
        source = '''
/* outer /* inner */ #Preview { */
Text("正式界面")
'''
        self.assertEqual(list(check.scan(check.without_previews(source))), ['正式界面'])

    def test_checker_entry_point_accepts_preview_only_factories(self):
        original = check.root
        try:
            with tempfile.TemporaryDirectory() as directory:
                check.root = pathlib.Path(directory)
                file = check.root / 'OpenGYM-iOS/Widgets/Example.swift'
                file.parent.mkdir(parents=True)
                file.write_text('''
#Preview { Widget() } contentStates: { Snapshot.canvas() }
private extension Snapshot {
    static func canvas() -> Self { Self(name: "预览样例") }
}
''')
                with redirect_stdout(io.StringIO()) as output:
                    check.main()
                self.assertIn('No hardcoded Chinese', output.getvalue())
        finally:
            check.root = original

    def test_checker_entry_point_rejects_runtime_copy_beside_preview_helpers(self):
        original = check.root
        try:
            with tempfile.TemporaryDirectory() as directory:
                check.root = pathlib.Path(directory)
                file = check.root / 'OpenGYM-iOS/Watch/Example.swift'
                file.parent.mkdir(parents=True)
                file.write_text('''
#Preview { SampleView(snapshot: .canvas()) }
private extension Snapshot {
    static func canvas() -> Self { Self(name: "预览样例") }
}
Text("正式界面")
''')
                with redirect_stdout(io.StringIO()) as output:
                    with self.assertRaises(SystemExit) as failure:
                        check.main()
                self.assertEqual(failure.exception.code, 1)
                self.assertIn('OpenGYM-iOS/Watch/Example.swift', output.getvalue())
                self.assertIn('正式界面', output.getvalue())
                self.assertNotIn('预览样例', output.getvalue())
        finally:
            check.root = original

    def test_interpolated_application_copy_is_still_checked(self):
        source = 'Text("VALUE \\(flag ? "中文" : "English")")'
        self.assertEqual(list(check.scan(check.without_previews(source))), ['中文'])


if __name__ == '__main__':
    unittest.main()
