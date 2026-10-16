import Foundation

enum MapTemplate: String, CaseIterable, Identifiable {
    case blank, project, meeting, study, writing, architecture, apiDesign, debugging, codeReview, release
    var id: String { rawValue }
    var isDeveloperTemplate: Bool { [.architecture, .apiDesign, .debugging, .codeReview, .release].contains(self) }
    var title: String {
        switch self {
        case .blank: "自由构思"
        case .project: "项目规划"
        case .meeting: "会议记录"
        case .study: "学习笔记"
        case .writing: "文章提纲"
        case .architecture: "系统设计"
        case .apiDesign: "API 设计"
        case .debugging: "Bug 排查"
        case .codeReview: "代码评审"
        case .release: "发布检查"
        }
    }
    var subtitle: String {
        switch self {
        case .blank: "从一个想法开始"
        case .project: "从目标到行动"
        case .meeting: "让讨论形成清晰结论"
        case .study: "连接知识与问题"
        case .writing: "梳理论点与表达"
        case .architecture: "梳理边界、依赖与技术取舍"
        case .apiDesign: "明确契约、异常与兼容策略"
        case .debugging: "从复现证据到根因与回归"
        case .codeReview: "检查正确性、可维护性与风险"
        case .release: "覆盖上线准备、观察与回滚"
        }
    }
    var symbol: String {
        switch self {
        case .blank: "sparkle"
        case .project: "flag.checkered"
        case .meeting: "person.3"
        case .study: "book"
        case .writing: "square.and.pencil"
        case .architecture: "server.rack"
        case .apiDesign: "network"
        case .debugging: "ladybug"
        case .codeReview: "chevron.left.forwardslash.chevron.right"
        case .release: "shippingbox"
        }
    }
    var document: MindMapDocument {
        func branch(_ title: String, _ children: [String]) -> MindMapNode {
            MindMapNode(title: title, children: children.map { MindMapNode(title: $0) })
        }
        var document = MindMapDocument()
        let branches: [MindMapNode]
        switch self {
        case .blank: branches = []
        case .project:
            branches = [branch("目标与价值", ["要解决的问题", "成功标准"]), branch("实施计划", ["关键里程碑", "工作分解"]), branch("资源与协作", ["参与角色", "时间与预算"]), branch("风险与验证", ["潜在风险", "验证方式"])]
        case .meeting:
            branches = [branch("讨论议题", ["背景与问题", "关键观点"]), branch("结论", ["已达成共识", "待确认问题"]), branch("行动项", ["负责人", "截止日期"])]
        case .study:
            branches = [branch("核心概念", ["定义", "与已有知识的联系"]), branch("案例与应用", ["典型案例", "自己的理解"]), branch("问题与复习", ["尚未理解", "下一步阅读"])]
        case .writing:
            branches = [branch("中心论点", ["读者与目的", "核心主张"]), branch("展开", ["论据一", "论据二", "反方观点"]), branch("收束", ["结论", "行动建议"])]
        case .architecture:
            branches = [
                branch("需求与约束", ["核心场景与非目标", "容量、延迟与可用性目标", "预算与合规约束"]),
                branch("模块与边界", ["客户端与接入层", "领域服务与责任划分", "外部依赖与接口契约"]),
                branch("数据与通信", ["数据模型与存储选型", "同步调用与异步消息", "缓存、一致性与幂等"]),
                branch("可靠性与安全", ["鉴权与权限边界", "超时、重试与降级", "监控、告警与灾备"]),
                branch("方案与演进", ["候选方案及取舍", "待验证假设", "里程碑与迁移路径"])
            ]
        case .apiDesign:
            branches = [
                branch("业务场景", ["调用方与使用目的", "资源与操作边界", "前置条件与权限"]),
                branch("请求契约", ["路径与 HTTP 方法", "参数、类型与校验", "认证头与幂等键"]),
                branch("响应契约", ["成功响应示例", "状态码与错误结构", "分页、排序与过滤"]),
                branch("安全与兼容", ["限流与敏感字段", "版本策略与弃用计划", "超时、重试与并发控制"]),
                branch("交付与验证", ["接口文档与 Mock", "契约测试与边界用例", "联调负责人及验收标准"])
            ]
        case .debugging:
            branches = [
                branch("问题现象", ["预期与实际结果", "影响范围与严重程度", "首次出现时间与版本"]),
                branch("稳定复现", ["最小复现步骤", "输入数据与环境", "发生频率与触发条件"]),
                branch("证据与假设", ["日志、调用栈与请求 ID", "最近代码或配置变更", "候选根因与排除证据"]),
                branch("修复方案", ["最小修复与风险", "临时缓解与回滚方式", "根因说明"]),
                branch("回归与复盘", ["复现用例与边界验证", "关联功能回归", "监控观察与预防措施"])
            ]
        case .codeReview:
            branches = [
                branch("变更背景", ["解决的问题与验收标准", "变更范围及关联需求", "方案取舍"]),
                branch("正确性", ["核心逻辑与边界条件", "错误处理与资源释放", "并发、事务与幂等"]),
                branch("设计与质量", ["职责划分与命名", "重复代码与复杂度", "兼容性与可读性"]),
                branch("安全与性能", ["权限、输入校验与敏感数据", "查询次数、缓存与内存", "依赖与配置风险"]),
                branch("验证与结论", ["测试证据与覆盖缺口", "阻塞问题与建议改进", "合并条件及跟进人"])
            ]
        case .release:
            branches = [
                branch("发布范围", ["版本号与变更清单", "负责人及发布时间", "影响服务与用户"]),
                branch("上线准备", ["构建产物与配置核对", "数据迁移及备份", "权限、依赖与兼容检查"]),
                branch("质量门禁", ["核心流程与回归结果", "性能及安全检查", "未解决问题与风险接受"]),
                branch("执行与观察", ["灰度范围及操作步骤", "成功指标与告警阈值", "日志、指标与值班人"]),
                branch("回滚与收尾", ["回滚触发条件", "回滚步骤与数据恢复", "发布公告与复盘记录"])
            ]
        }
        document.nodes = [MindMapNode(title: self == .blank ? "中心主题" : title, children: branches)]
        document.title = document.root.title
        AppPreferences.prepareNewMap(&document)
        return document
    }
}
