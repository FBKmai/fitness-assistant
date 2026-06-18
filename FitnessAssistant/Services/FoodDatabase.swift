import Foundation

/// 本地食物成分库的一条记录（每 100g 可食部）。
struct FoodCompositionEntry {
    var name: String
    var aliases: [String]
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double
    var sodiumMg: Double
}

/// 给定克数后，按成分库算出的某食物宏量（绝对值）。
struct FoodMacroResult {
    var matchedName: String
    var grams: Double
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double
    var sodiumMg: Double
}

/// 本地食物成分库：根治「AI 自己编热量」。AI 只负责识别食物名 + 估克数，数值在这里按每 100g 标准值换算。
///
/// 数据为常见食物的近似每 100g 值（参考《中国食物成分表》等公开口径，烹饪态以常见做法为准），
/// 仅作估算基准，可持续扩充。匹配复用与 FoodOption 一致的归一化（去空格/「的」等）。
final class FoodDatabase {
    static let shared = FoodDatabase()

    private(set) var entries: [FoodCompositionEntry] = []

    private init() {
        entries = Self.parse(Self.raw)
    }

    /// 模糊匹配：精确名/别名优先，其次包含关系。匹配不到返回 nil（调用方应回退到 AI 估算）。
    func match(_ query: String) -> FoodCompositionEntry? {
        let q = Self.normalize(query)
        guard !q.isEmpty else { return nil }
        var contains: FoodCompositionEntry?
        for e in entries {
            let terms = ([e.name] + e.aliases).map(Self.normalize)
            if terms.contains(q) { return e }
            if contains == nil, terms.contains(where: { ($0.count >= 2 && q.contains($0)) || ($0.contains(q) && q.count >= 2) }) {
                contains = e
            }
        }
        return contains
    }

    /// 按克数换算某食物的宏量；匹配不到返回 nil。
    func macros(for query: String, grams: Double) -> FoodMacroResult? {
        guard grams > 0, let e = match(query) else { return nil }
        let r = grams / 100
        return FoodMacroResult(
            matchedName: e.name,
            grams: grams,
            kcal: e.kcal * r,
            protein: e.protein * r,
            carbs: e.carbs * r,
            fat: e.fat * r,
            fiber: e.fiber * r,
            sodiumMg: e.sodiumMg * r
        )
    }

    // MARK: - 解析

    private static func parse(_ text: String) -> [FoodCompositionEntry] {
        var result: [FoodCompositionEntry] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let row = line.trimmingCharacters(in: .whitespaces)
            if row.isEmpty || row.hasPrefix("#") { continue }
            let cols = row.components(separatedBy: "|")
            guard cols.count >= 5 else { continue }
            func num(_ i: Int) -> Double {
                guard i < cols.count else { return 0 }
                return Double(cols[i].trimmingCharacters(in: .whitespaces)) ?? 0
            }
            let aliases = cols.count >= 8
                ? cols[7].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                : []
            result.append(FoodCompositionEntry(
                name: cols[0].trimmingCharacters(in: .whitespaces),
                aliases: aliases,
                kcal: num(1),
                protein: num(2),
                carbs: num(3),
                fat: num(4),
                fiber: num(5),
                sodiumMg: num(6)
            ))
        }
        return result
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "的", with: "")
            .replacingOccurrences(of: "一份", with: "")
            .replacingOccurrences(of: "之前那个", with: "")
            .replacingOccurrences(of: "之前的", with: "")
    }

    // MARK: - 数据（name|kcal|protein|carbs|fat|fiber|sodiumMg|aliases，均为每 100g 可食部近似值）

    private static let raw = """
    # 蛋奶豆
    鸡蛋|143|13|1|10|0|130|全蛋,水煮蛋,茶叶蛋,煎蛋
    蛋白|52|11|0.7|0.2|0|160|鸡蛋白,蛋清
    蛋黄|328|16|3|27|0|50|鸡蛋黄
    牛奶|60|3|5|3.2|0|50|全脂牛奶,纯牛奶
    脱脂牛奶|35|3.4|5|0.2|0|52|低脂牛奶
    酸奶|72|3.3|9|3.2|0|45|无糖酸奶,原味酸奶
    豆浆|31|3|1.2|1.6|0.6|3|无糖豆浆
    北豆腐|116|12|3|7|0.5|10|老豆腐,卤水豆腐
    嫩豆腐|70|7|2|4|0.4|8|内酯豆腐,南豆腐
    豆干|140|17|6|6|1|330|豆腐干,香干
    # 肉禽鱼虾
    鸡胸肉|118|24|0|1.9|0|45|鸡胸,水煮鸡胸
    鸡腿肉|181|24|0|9|0|85|去皮鸡腿,鸡腿
    鸡排|165|22|3|7|0|420|香煎鸡排,无油鸡排
    牛肉|160|22|2|7|0|55|瘦牛肉,牛里脊,水煮牛肉
    牛排|220|26|0|13|0|60|煎牛排
    猪里脊|155|22|1|7|0|55|里脊肉,瘦猪肉
    五花肉|395|9|0|39|0|50|带皮五花
    羊肉|203|19|0|14|0|70|瘦羊肉,羊排
    三文鱼|208|22|0|13|0|60|生鱼片,三文鱼刺身
    鳕鱼|105|23|0|1|0|70|鳕鱼排
    虾|99|24|0|0.3|0|150|虾仁,基围虾,白虾
    金枪鱼|130|26|0|3|0|45|吞拿鱼
    香肠|420|14|3|39|0|900|火腿肠
    # 主食碳水
    米饭|116|2.6|25|0.3|0.3|2|白米饭,熟米饭
    杂粮饭|130|3|27|1|2|2|糙米饭,五谷饭
    白粥|46|0.9|10|0.1|0.1|2|大米粥,稀饭
    馒头|221|7|47|1|1.3|160|白馒头
    包子|240|8|40|6|1.5|330|肉包,菜包
    蒸饺|210|8|28|7|1|360|饺子,水饺
    面条|110|4|24|0.5|0.9|180|煮面,面
    全麦面包|250|9|48|3.5|6|400|全麦吐司
    吐司|280|8|50|6|2|450|白吐司,面包
    燕麦|380|13|60|7|9|3|燕麦片,干燕麦
    红薯|90|1.6|20|0.1|2.2|28|地瓜,蒸红薯
    紫薯|82|1.5|18|0.2|2.2|10|蒸紫薯
    土豆|87|2|20|0.1|1.2|6|马铃薯,蒸土豆
    玉米|106|4|22|1.5|2.9|1|甜玉米,鲜玉米,煮玉米
    年糕|154|3|34|0.5|0.4|40|
    粿条|110|2.5|24|0.6|0.5|200|河粉,米粉,米线
    # 蔬菜
    西兰花|34|2.8|7|0.4|2.6|20|西蓝花
    生菜|15|1.4|2|0.2|1.3|10|油麦菜
    白菜|17|1.5|3|0.2|0.8|57|大白菜
    娃娃菜|13|1.5|2|0.2|1|30|
    菠菜|24|2.6|3.6|0.4|1.7|85|
    黄瓜|16|0.8|3.6|0.2|0.5|5|青瓜
    番茄|18|0.9|3.9|0.2|0.5|5|西红柿,圣女果
    胡萝卜|41|0.9|10|0.2|2.8|70|
    西葫芦|17|1.2|3.4|0.2|1|8|
    南瓜|26|1|6.5|0.1|0.8|1|
    香菇|26|2.2|3.3|0.2|2.5|2|鲜香菇,蘑菇,口蘑
    金针菇|26|2.4|3.3|0.4|2.7|4|
    海带|13|1.2|2.1|0.1|0.5|240|裙带菜
    木耳|21|1.5|6|0.2|2.6|9|黑木耳,泡发木耳
    豆芽|18|3|2.6|0.1|1.2|5|绿豆芽,黄豆芽
    芹菜|14|1.2|3.3|0.2|1.2|80|
    茄子|21|1.1|5|0.2|1.3|5|
    # 水果
    苹果|52|0.3|14|0.2|2.4|1|莲雾
    香蕉|93|1.4|23|0.2|1.2|1|
    西瓜|30|0.6|8|0.2|0.4|3|
    橙子|48|0.8|12|0.2|1.6|1|橙,柳橙
    椰子水|19|0.7|3.7|0.2|1.1|105|椰汁
    羊角蜜|35|0.6|9|0.1|0.5|2|甜瓜,香瓜
    # 坚果油脂酱料
    花生|567|26|16|49|8.5|18|花生米
    杏仁|579|21|22|50|12|1|巴旦木
    黑巧克力|600|9|30|46|10|20|85%黑巧
    食用油|900|0|0|100|0|0|植物油,花生油,橄榄油
    芝麻酱|618|20|22|53|6|40|麻酱
    沙拉酱|680|1|6|73|0|600|蛋黄酱,千岛酱
    # 饮料零食
    无糖可乐|0.4|0|0|0|0|10|零度可乐,无糖汽水
    黑咖啡|2|0.2|0|0|0|2|美式咖啡,意式浓缩,espresso
    魔芋爽|130|2|18|5|3|1200|魔芋
    牛肉干|385|60|18|7|0|927|牛脆条,风干牛肉
    """
}
