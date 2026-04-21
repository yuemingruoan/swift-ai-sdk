import Foundation
import Testing
@testable import AppleHostExampleSupport

struct AppleHostExampleLocalizationTests {
    @Test func uses_english_strings_when_language_is_english() {
        let strings = AppleHostExampleStrings(
            language: .english,
            locale: Locale(identifier: "zh-Hans_CN")
        )

        #expect(strings.windowTitle == "Apple Host Example")
        #expect(strings.signIn == "Sign In with ChatGPT")
        #expect(strings.demoPrompts == "Demo Prompts")
    }

    @Test func uses_simplified_chinese_strings_when_language_is_system_and_locale_is_zh_hans() {
        let strings = AppleHostExampleStrings(
            language: .system,
            locale: Locale(identifier: "zh-Hans_CN")
        )

        #expect(strings.windowTitle == "Apple 平台示例")
        #expect(strings.signIn == "使用 ChatGPT 登录")
        #expect(strings.demoPrompts == "示例提示词")
    }
}
