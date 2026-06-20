import json
from pathlib import Path

# Crystal Dermatology (晶肤医美) core project knowledge base
# 5 lightweight medical aesthetics projects

KNOWLEDGE = [
    {
        "name": "光子嫩肤",
        "suitable": "肤色暗沉、浅层色斑、红血丝、细小皱纹、毛孔粗大",
        "principle": "强脉冲光穿透皮肤，分解色素、闭合异常毛细血管、刺激胶原再生",
        "price": "1500-2500元/次",
        "recovery": "无恢复期，当天轻微泛红可消退",
        "qa": [
            "光子嫩肤疼吗？基本不疼，像皮筋弹到皮肤的感觉。",
            "做几次有效果？一般3-5次一个疗程，每次间隔一个月。"
        ]
    },
    {
        "name": "果酸焕肤",
        "suitable": "痘痘、痘印、毛孔粗大、皮肤粗糙、油脂分泌旺盛",
        "principle": "不同浓度果酸促进老化角质脱落，加速皮肤更新，改善肤质",
        "price": "800-1500元/次",
        "recovery": "1-2天微红脱屑",
        "qa": [
            "敏感肌能做吗？医生会根据皮肤情况选择适合的浓度。",
            "做完能化妆吗？建议24小时后再化妆。"
        ]
    },
    {
        "name": "水光针",
        "suitable": "皮肤干燥、缺水、细纹、肤色不均、毛孔粗大",
        "principle": "将透明质酸等营养成分直接注入真皮层，深层补水保湿",
        "price": "2000-4000元/次",
        "recovery": "针眼当天消退，可正常护肤",
        "qa": [
            "水光针有副作用吗？短时间可能轻微红肿淤青，很快消退。",
            "能维持多久？一般1-3个月，建议按疗程打效果更好。"
        ]
    },
    {
        "name": "超皮秒",
        "suitable": "各类色斑（雀斑、晒斑、褐青色痣等）、纹身、肤色暗沉",
        "principle": "超短脉冲激光瞬间击碎色素颗粒，由身体代谢排出",
        "price": "3000-6000元/次",
        "recovery": "结痂7-10天脱落，期间注意防晒",
        "qa": [
            "会不会反黑？术后严格防晒很重要，医生会指导护理。",
            "几次能祛干净？看斑的类型和深度，通常2-5次。"
        ]
    },
    {
        "name": "除皱瘦脸针",
        "suitable": "动态纹（鱼尾纹、抬头纹、川字纹）、咬肌肥大",
        "principle": "阻断神经肌肉信号传递，减少肌肉活动，达到除皱和瘦脸效果",
        "price": "2000-5000元/次",
        "recovery": "无恢复期，当天即可正常活动",
        "qa": [
            "会脸僵吗？正规医生操作表情依然自然。",
            "能维持多久？一般4-6个月，可定期补打。"
        ]
    }
]

# Format each project as a searchable text document
def get_knowledge_docs():
    docs = []
    for item in KNOWLEDGE:
        doc_text = (
            f"项目名称：{item['name']}\n"
            f"适用人群：{item['suitable']}\n"
            f"治疗原理：{item['principle']}\n"
            f"参考价格：{item['price']}\n"
            f"恢复期：{item['recovery']}\n"
            f"常见问答：{'；'.join(item['qa'])}"
        )
        docs.append({"text": doc_text, "metadata": item})
    return docs
