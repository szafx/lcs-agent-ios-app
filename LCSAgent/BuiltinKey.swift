import Foundation

/// 内置 API Key。
///
/// 仓库里这份是**空串**，避免公开仓库泄露。
/// GitHub Actions 构建时会用 Secret `XC_API_KEY` 覆盖生成本文件，
/// 所以流水线出来的 IPA 里是带 Key 的，仓库里没有。
///
/// 本地想内置 Key：直接改下面的 value（别提交）。
enum BuiltinKey {
    static let value = ""
}
