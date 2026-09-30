# -*- coding: utf-8 -*-
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Patch, FancyArrowPatch
import math

plt.rcParams["font.family"] = "DejaVu Sans"

def shadow_frame(ax, x0, y0, w, h, facecolor, edgecolor, zorder, rounding=0.15):
    shadow = FancyBboxPatch((x0 + 0.06, y0 - 0.06), w, h, boxstyle=f"round,pad=0.02,rounding_size={rounding}",
                             linewidth=0, facecolor="#000000", alpha=0.15, zorder=zorder)
    ax.add_patch(shadow)
    frame = FancyBboxPatch((x0, y0), w, h, boxstyle=f"round,pad=0.02,rounding_size={rounding}",
                            linewidth=1.2, edgecolor=edgecolor, facecolor=facecolor, zorder=zorder + 0.1)
    ax.add_patch(frame)

W, H = 15.4, 9.5
fig, ax = plt.subplots(figsize=(W, H), dpi=200)
ax.set_xlim(0, W); ax.set_ylim(0, H); ax.axis("off")
C_VM1, C_VM2, C_PC, C_SW = "#1D3557", "#2A6F4B", "#8A4B08", "#333333"
ax.text(W/2, H-0.5, "ARCHITECTURE RESEAU \u2014 WAZ_ELK_FACTORY", ha="center", va="center", fontsize=22, fontweight="bold", color="#0D1B2A")
ax.text(W/2, H-1.05, "Reseau prive de laboratoire \u2014 192.168.50.0/24", ha="center", va="center", fontsize=13.5, style="italic", color="#444444")
net_box = FancyBboxPatch((0.4, 0.4), W-0.8, H-1.8, boxstyle="round,pad=0.02,rounding_size=0.25", linewidth=2, edgecolor="#8896A6", facecolor="#EDF2F7", zorder=0)
ax.add_patch(net_box)
BOX_TOP = H - 2.3; BOX_H = 4.6; BOX_W = 4.3
GAP = (W - 0.8 - 3*BOX_W) / 4
xs = [0.4 + GAP + i*(BOX_W+GAP) for i in range(3)]

def server_box(x, top, w, h, title, subtitle, groups, color, frame_color):
    y = top - h
    box = FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.02,rounding_size=0.12", linewidth=1.5, edgecolor="#0D1B2A", facecolor=color, zorder=2)
    ax.add_patch(box)
    cx = x + w/2
    ax.text(cx, top-0.42, title, ha="center", va="top", fontsize=14.5, fontweight="bold", color="white", zorder=4)
    ax.text(cx, top-0.9, subtitle, ha="center", va="top", fontsize=11.5, color="#E4ECF5", style="italic", zorder=4)
    ty = top - 1.45; line_h = 0.4
    for group_label, items in groups:
        group_top = ty + 0.14; n = len(items); group_h = n*line_h + 0.12
        if group_label:
            shadow_frame(ax, x+0.18, group_top-group_h, w-0.36, group_h, frame_color, "#00000030", zorder=2.3, rounding=0.09)
            ax.text(x+0.32, group_top-0.06, group_label, ha="left", va="top", fontsize=9.3, color="#1a1a1a", fontweight="bold", style="italic", zorder=4)
            ty -= 0.34
        for it in items:
            ax.text(x+0.34, ty, "\u2022 " + it, ha="left", va="top", fontsize=10.6, color="white", zorder=4)
            ty -= line_h
        ty -= 0.16
    return (cx, y)

vm1_groups = [("Fondation", ["PKI (autorite de certification interne)"]),
              ("Pile ELK", ["Elasticsearch (9202) + Logstash", "Kibana (5601)"]),
              ("Pile Wazuh", ["Wazuh Manager (1514/1515) + API (55000)", "Wazuh Indexer (9200) + Dashboard (443)"])]
vm2_groups = [("Agent de securite", ["Agent Wazuh"]), ("Beats (collecte)", ["Filebeat", "Metricbeat"])]
pc_groups = [("Agents (memes que VM2)", ["Agent Wazuh", "Filebeat", "Metricbeat"]),
             ("Usage humain", ["Navigateur (Kibana / Wazuh Dashboard)", "Console d'administration ($APP_BIN)"])]

vm1_bottom = server_box(xs[0], BOX_TOP, BOX_W, BOX_H, "VM1 \u2014 ELK_HOST", "192.168.50.128", vm1_groups, C_VM1, "#3E5C82")
vm2_bottom = server_box(xs[1], BOX_TOP, BOX_W, BOX_H, "VM2 \u2014 AGENT_HOST", "192.168.50.130 (Linux)", vm2_groups, C_VM2, "#4A8F6B")
pc_bottom = server_box(xs[2], BOX_TOP, BOX_W, BOX_H, "Poste physique", "192.168.50.1 (Windows, VMnet8/NAT)", pc_groups, C_PC, "#B0742E")

sw_cx, sw_cy = W/2, 1.55; sw_w, sw_h = 4.6, 1.05
sw_box = FancyBboxPatch((sw_cx-sw_w/2, sw_cy-sw_h/2), sw_w, sw_h, boxstyle="round,pad=0.02,rounding_size=0.1", linewidth=1.5, edgecolor="#0D1B2A", facecolor=C_SW, zorder=2)
ax.add_patch(sw_box)
ax.text(sw_cx, sw_cy+0.12, "Segment reseau partage", ha="center", va="center", fontsize=12.5, fontweight="bold", color="white", zorder=3)
ax.text(sw_cx, sw_cy-0.28, "192.168.50.0/24", ha="center", va="center", fontsize=11, color="#D8D8D8", style="italic", zorder=3)

def link(p_box, ports_label):
    x0, y0 = p_box
    ax.plot([x0, sw_cx], [y0, sw_cy+sw_h/2], color="#333333", linewidth=1.8, zorder=1, solid_capstyle="round")
    mx, my = (x0+sw_cx)/2, (y0+sw_cy+sw_h/2)/2
    ax.text(mx, my, ports_label, ha="center", va="center", fontsize=10.5, color="#111111", zorder=5,
            bbox=dict(boxstyle="round,pad=0.25", facecolor="white", edgecolor="#999999"))

link(vm1_bottom, "1514/1515\n5044 \u00b7 5601 \u00b7 443")
link(vm2_bottom, "1514/1515\n5044")
link(pc_bottom, "1514/1515\n5044 \u00b7 5601 \u00b7 443")

legend_handles = [Patch(facecolor=C_VM1, edgecolor="#0D1B2A", label="VM1 \u2014 ELK_HOST (192.168.50.128)"),
                   Patch(facecolor=C_VM2, edgecolor="#0D1B2A", label="VM2 \u2014 AGENT_HOST (192.168.50.130)"),
                   Patch(facecolor=C_PC, edgecolor="#0D1B2A", label="Poste physique (192.168.50.1)")]
leg = ax.legend(handles=legend_handles, loc="lower center", bbox_to_anchor=(0.5, -0.02), ncol=3, frameon=True, fontsize=11, edgecolor="#8896A6", facecolor="white", framealpha=1)
leg.get_frame().set_linewidth(1.2)
plt.tight_layout()
plt.savefig("C:/Users/HP PROBOOK/Documents/WEF/img_archi_physique.png", dpi=200, facecolor="white", bbox_inches="tight")
plt.close()
print("1/3 physique OK")

W, H = 16.5, 10.5
fig, ax = plt.subplots(figsize=(W, H), dpi=200)
ax.set_xlim(0, W); ax.set_ylim(0, H); ax.axis("off")
ax.text(W/2, H-0.5, "ARCHITECTURE LOGIQUE \u2014 COMMUNICATION ENTRE COMPOSANTS", ha="center", va="center", fontsize=20, fontweight="bold", color="#0D1B2A")
ax.text(W/2, H-1.0, "Chaque fleche porte son protocole reel \u2014 tout flux interne est chiffre (TLS/SSL, PKI interne)", ha="center", va="center", fontsize=12.5, style="italic", color="#444444")

def box(x, y, w, h, text, color, fontsize=10.5, zorder=3):
    b = FancyBboxPatch((x-w/2, y-h/2), w, h, boxstyle="round,pad=0.02,rounding_size=0.09", linewidth=1.3, edgecolor="#222222", facecolor=color, zorder=zorder)
    ax.add_patch(b)
    ax.text(x, y, text, ha="center", va="center", fontsize=fontsize, color="white", fontweight="bold", zorder=zorder+1)
    return (x, y, w, h)

def edge_point(b, direction):
    x, y, w, h = b; dx, dy = direction
    if dx > 0: return (x+w/2, y)
    if dx < 0: return (x-w/2, y)
    if dy > 0: return (x, y+h/2)
    return (x, y-h/2)

def arrow(p1, p2, label, color="#333333", style="-|>", ls="solid", lw=1.6, nudge=0.0, labelcolor="#111111", fontsize=9.3):
    a = FancyArrowPatch(p1, p2, arrowstyle=style, mutation_scale=14, linewidth=lw, color=color, linestyle=ls, zorder=2)
    ax.add_patch(a)
    mx, my = (p1[0]+p2[0])/2, (p1[1]+p2[1])/2
    dx, dy = p2[0]-p1[0], p2[1]-p1[1]
    length = max(0.001, math.hypot(dx, dy))
    px, py = -dy/length, dx/length
    mx += px*nudge; my += py*nudge
    if label:
        ax.text(mx, my, label, ha="center", va="center", fontsize=fontsize, color=labelcolor, zorder=5,
                bbox=dict(boxstyle="round,pad=0.22", facecolor="white", edgecolor="#AAAAAA", alpha=0.97))

shadow_frame(ax, 0.3, 0.3, 3.5, H-1.9, "#EDF2F7", "#8896A6", 0, rounding=0.2)
ax.text(2.05, H-1.75, "SOURCES (agents)", ha="center", fontsize=11, fontweight="bold", color="#556070")
shadow_frame(ax, 4.1, 0.3, 8.6, H-1.9, "#F5F7FA", "#8896A6", 0, rounding=0.2)
ax.text(8.4, H-1.75, "VM1 \u2014 ELK_HOST (192.168.50.128)", ha="center", fontsize=11, fontweight="bold", color="#556070")
shadow_frame(ax, 13.0, 0.3, 3.2, H-1.9, "#EDF2F7", "#8896A6", 0, rounding=0.2)
ax.text(14.6, H-1.85, "OPERATEUR & EXTERNE", ha="center", fontsize=9.8, fontweight="bold", color="#556070")

agent_pc = box(2.05, 6.9, 2.9, 0.95, "Agent Wazuh +\nFilebeat + Metricbeat\n(192.168.50.1)", "#8A4B08")
agent_vm2 = box(2.05, 4.4, 2.9, 0.95, "Agent Wazuh +\nFilebeat + Metricbeat\n(192.168.50.130)", "#2A6F4B")
wazuh_mgr = box(6.4, 8.3, 2.6, 0.8, "Wazuh Manager\n(1514/1515)", "#1D3557")
alerts_f = box(9.7, 8.3, 2.0, 0.7, "alerts.json", "#4A4A4A", fontsize=9.5)
logstash = box(6.4, 6.6, 2.2, 0.7, "Logstash", "#3D5A80")
es = box(5.2, 4.7, 2.2, 0.8, "Elasticsearch\n(9202)", "#3D5A80")
wi = box(9.9, 4.7, 2.3, 0.8, "Wazuh Indexer\n(9200)", "#1D3557")
kibana = box(5.2, 2.3, 2.2, 0.7, "Kibana\n(5601)", "#3D5A80")
wdash = box(9.9, 2.3, 2.3, 0.7, "Wazuh Dashboard\n(443)", "#1D3557")
vt_api = box(14.6, 8.3, 2.6, 0.9, "VirusTotal\n(API externe)", "#6B3FA0")
browser = box(14.6, 1.1, 2.6, 0.9, "Navigateur operateur\n(192.168.50.1)", "#8A4B08")

arrow(edge_point(agent_pc, (1, 0.3)), edge_point(wazuh_mgr, (-1, -0.3)), "1514/1515 \u00b7 TLS", nudge=0.22)
arrow(edge_point(agent_pc, (1, -0.3)), edge_point(logstash, (-1, 0.4)), "5044 \u00b7 TLS", nudge=-0.22)
arrow(edge_point(agent_vm2, (1, 0.3)), edge_point(wazuh_mgr, (-1, -0.9)), "1514/1515 \u00b7 TLS", nudge=0.22)
arrow(edge_point(agent_vm2, (1, -0.3)), edge_point(logstash, (-1, -0.2)), "5044 \u00b7 TLS", nudge=-0.22)
arrow(edge_point(wazuh_mgr, (1, 0)), edge_point(alerts_f, (-1, 0)), "ecrit", color="#555555", lw=1.2, fontsize=8.5)
arrow(edge_point(alerts_f, (0, -1)), edge_point(logstash, (1, 0.3)), "lit", color="#555555", lw=1.2, nudge=0.15, fontsize=8.5)
arrow(edge_point(logstash, (-1, -0.3)), edge_point(es, (0, 1)), "TLS \u00b7 mode Kibana", nudge=0.2)
arrow(edge_point(logstash, (1, -0.3)), edge_point(wi, (0, 1)), "TLS \u00b7 mode Wazuh", nudge=-0.2)
arrow(edge_point(es, (0, -1)), edge_point(kibana, (0, 1)), "TLS", fontsize=9)
arrow(edge_point(wi, (0, -1)), edge_point(wdash, (0, 1)), "TLS", fontsize=9)
arrow(edge_point(es, (1, 0)), edge_point(wi, (-1, 0)), "", color="#6B3FA0", ls="dashed", lw=2.4, style="<|-|>")
ax.text((es[0]+es[2]/2+wi[0]-wi[2]/2)/2, es[1]-0.75, "BASCULE DE DONNEES\n(verifiee, sans perte)", ha="center", va="center",
        fontsize=9.8, color="#6B3FA0", fontweight="bold", zorder=5, bbox=dict(boxstyle="round,pad=0.3", facecolor="#F3E9FB", edgecolor="#6B3FA0"))
arrow(edge_point(wazuh_mgr, (1, 0.2)), edge_point(vt_api, (-1, 0.2)), "HTTPS\n(hash de fichier)", color="#6B3FA0", nudge=0.3, fontsize=8.8)
arrow(edge_point(kibana, (0, -1)), edge_point(browser, (-1, 0.25)), "HTTPS \u00b7 5601", nudge=-0.35, fontsize=8.8)
arrow(edge_point(wdash, (0, -1)), edge_point(browser, (-1, -0.1)), "HTTPS \u00b7 443", nudge=0.3, fontsize=8.8)

legend_handles = [Patch(facecolor="#8A4B08", edgecolor="#222", label="Poste physique / operateur"),
                   Patch(facecolor="#2A6F4B", edgecolor="#222", label="VM2 (agent Linux)"),
                   Patch(facecolor="#1D3557", edgecolor="#222", label="Composants Wazuh"),
                   Patch(facecolor="#3D5A80", edgecolor="#222", label="Composants ELK"),
                   Patch(facecolor="#6B3FA0", edgecolor="#222", label="Bascule de donnees / service externe")]
leg = ax.legend(handles=legend_handles, loc="lower center", bbox_to_anchor=(0.5, -0.05), ncol=5, frameon=True, fontsize=9.5, edgecolor="#8896A6", facecolor="white", framealpha=1)
leg.get_frame().set_linewidth(1.1)
plt.tight_layout()
plt.savefig("C:/Users/HP PROBOOK/Documents/WEF/img_archi_logique.png", dpi=200, facecolor="white", bbox_inches="tight")
plt.close()
print("2/3 logique OK")

DONE = "#3C8F5C"; TODO = "#C97A2B"; VERIF = "#B8860B"; ROOT_C = "#0D1B2A"; WAZUH_C = "#1D3557"; ELK_C = "#3D5A80"; COMPL_C = "#0E7C7B"
TREE = [
    ("Securite", "#1D3557", "#DCE8F5", [
        ("Detection\nd'intrusion", "#3D5A80", [("Heures\nouvrees", VERIF, "wazuh"), ("Depart\nen conge", VERIF, "wazuh"), ("Rootcheck\n+ Auditd", DONE, "wazuh")]),
        ("Detection de\nvulnerabilites", "#3D5A80", [("Scan\nnmap", DONE, "compl-nmap"), ("Alerte MAJ\nediteur", VERIF, "compl-nmap"), ("Appareil\nintrus", VERIF, "compl-nmap")]),
        ("Sante des\nfichiers", "#3D5A80", [("VirusTotal", DONE, "compl-vt")]),
    ]),
    ("Applications", "#7A4B12", "#FBEBD6", [
        ("Collecte des\ndonnees monetiques", "#A56A1E", [("Collecte\nmonetique", DONE, "elk")]),
        ("Conformite\nfinanciere (LCB-FT)", "#A56A1E", [("Embargo\nBEAC", DONE, "elk"), ("Fraude compte\ndormant", VERIF, "elk")]),
    ]),
    ("Continuite de\nla donnee", "#5B3A8E", "#E8DFF5", [
        ("Bascule de\ndonnees (Data Cutover)", "#7C57B5", [("Wazuh Indexer\n<-> Elasticsearch", DONE, "both")]),
    ]),
]
OBJ_FRAME = {"Securite": "#C9DCF0", "Applications": "#F3DBB8", "Continuite de\nla donnee": "#D9CBEE"}
LEAF_SLOT = 2.0; LEAF_W = 1.75
n_leaves = sum(len(leaves) for _, _, _, objs in TREE for _, _, leaves in objs)
total_w = n_leaves * LEAF_SLOT + 1.4
total_h = 12.6
fig, ax = plt.subplots(figsize=(total_w, total_h), dpi=200)
ax.set_xlim(0, total_w); ax.set_ylim(0, total_h); ax.axis("off")
ax.text(total_w/2, total_h-0.5, "ARBORESCENCE DES OBJECTIFS \u2014 WAZ_ELK_FACTORY", ha="center", va="center", fontsize=21, fontweight="bold", color="#0D1B2A")
ax.text(total_w/2, total_h-1.02, "Du sens vers le systeme : chaque objectif descend jusqu'a la solution qui le satisfait reellement", ha="center", va="center", fontsize=12.8, style="italic", color="#444444")

def node(x, y, w, h, text, color, fontsize, edgecolor="#222222", ls="solid", lw=1.3):
    b = FancyBboxPatch((x-w/2, y-h/2), w, h, boxstyle="round,pad=0.02,rounding_size=0.09", linewidth=lw, edgecolor=edgecolor, facecolor=color, zorder=3, linestyle=ls)
    ax.add_patch(b)
    ax.text(x, y, text, ha="center", va="center", fontsize=fontsize, color="white", fontweight="bold" if fontsize >= 11 else "normal", zorder=4)
    return (x, y+h/2), (x, y-h/2), (x-w/2, y), (x+w/2, y)

def connect(p1, p2, color="#8A8A8A", lw=1.3, ls="solid", zorder=2):
    ax.plot([p1[0], p2[0]], [p1[1], p2[1]], color=color, linewidth=lw, zorder=zorder, linestyle=ls)

Y_ROOT = total_h - 1.9; Y_DISC = Y_ROOT - 1.75; Y_OBJ = Y_DISC - 1.75; Y_LEAF = Y_OBJ - 1.75
Y_NOTE = Y_LEAF - 1.55; Y_TECH = Y_NOTE - 1.1; Y_COMPL = Y_TECH - 1.55
LEAF_H, OBJ_H, DISC_H = 0.95, 0.75, 0.7; PAD = 0.32
slot_cursor = 0.7 + LEAF_SLOT/2
disc_centers = []; leaf_records = []
for disc_label, disc_color, disc_frame_color, objs in TREE:
    obj_centers = []; disc_leaf_xmin, disc_leaf_xmax = None, None
    for obj_label, obj_color, leaves in objs:
        first_x = slot_cursor - LEAF_SLOT/2
        leaf_xs = [first_x + LEAF_SLOT*(i+0.5) for i in range(len(leaves))]
        last_x = first_x + LEAF_SLOT*len(leaves)
        slot_cursor = last_x + LEAF_SLOT/2
        shadow_frame(ax, first_x+0.12, Y_LEAF-LEAF_H/2-PAD*0.5, (last_x-first_x)-0.24, LEAF_H+PAD, OBJ_FRAME[disc_label], "#9AA7B5", zorder=0.5, rounding=0.18)
        obj_x = sum(leaf_xs)/len(leaf_xs)
        obj_top, obj_bot, *_ = node(obj_x, Y_OBJ, 2.3, OBJ_H, obj_label, obj_color, 11)
        for x, (leaf_label, leaf_color, tech) in zip(leaf_xs, leaves):
            top, bot, *_ = node(x, Y_LEAF, LEAF_W, LEAF_H, leaf_label, leaf_color, 10.2)
            connect(obj_bot, top)
            leaf_records.append((x, bot, tech, leaf_color))
        obj_centers.append((obj_x, obj_top, obj_bot))
        if disc_leaf_xmin is None or first_x < disc_leaf_xmin: disc_leaf_xmin = first_x
        if disc_leaf_xmax is None or last_x > disc_leaf_xmax: disc_leaf_xmax = last_x
    disc_x = sum(c[0] for c in obj_centers)/len(obj_centers)
    shadow_frame(ax, disc_leaf_xmin, Y_LEAF-LEAF_H/2-PAD, (disc_leaf_xmax-disc_leaf_xmin), (Y_OBJ+OBJ_H/2+PAD)-(Y_LEAF-LEAF_H/2-PAD), disc_frame_color, "#8A94A0", zorder=0.1, rounding=0.2)
    disc_top, disc_bot, *_ = node(disc_x, Y_DISC, 2.5, DISC_H, disc_label.upper(), disc_color, 12.5)
    for ox, otop, obot in obj_centers: connect(disc_bot, otop)
    disc_centers.append((disc_x, disc_top))
root_x = sum(c[0] for c in disc_centers)/len(disc_centers)
root_top, root_bot, *_ = node(root_x, Y_ROOT, 2.9, 0.6, "WAZ_ELK_FACTORY", ROOT_C, 13)
for dx, dtop in disc_centers: connect(root_bot, dtop)

ax.text(total_w/2, Y_NOTE, "APRES ETUDE COMPARATIVE DES SOLUTIONS DU MARCHE (payantes et open-source)", ha="center", va="center",
        fontsize=11.5, fontweight="bold", color="#333333", zorder=6, bbox=dict(boxstyle="round,pad=0.35", facecolor="white", edgecolor="#CCCCCC"))
wazuh_leaves = [r for r in leaf_records if r[2] in ("wazuh", "both", "compl-nmap", "compl-vt")]
elk_leaves = [r for r in leaf_records if r[2] in ("elk", "both")]
wazuh_x = sum(r[0] for r in wazuh_leaves)/len(wazuh_leaves)
elk_x = sum(r[0] for r in elk_leaves)/len(elk_leaves)
if elk_x - wazuh_x < 5.0: elk_x = wazuh_x + 5.0
wazuh_top, wazuh_bot, wazuh_left, wazuh_right = node(wazuh_x, Y_TECH, 3.0, 0.85, "SIEM\nWAZUH", WAZUH_C, 13.5)
elk_top, elk_bot, elk_left, elk_right = node(elk_x, Y_TECH, 3.0, 0.85, "PILE\nELK", ELK_C, 13.5)
# REVU LE 2026-09-30 (demande explicite : les fleches vers SIEM Wazuh,
# Pile ELK, nmap et VirusTotal doivent se distinguer sans effort visuel)
# - chaque destination a desormais SA PROPRE couleur (celle de sa propre
# boite, deja lue par l'oeil) et un trait plus epais - jamais un gris
# neutre identique pour deux destinations differentes.
NMAP_C = COMPL_C          # teal, deja la couleur de la boite nmap
VT_C = "#B33C7A"          # rose/magenta, distinct de tout le reste de la palette
for x, bot, tech, color in leaf_records:
    if tech == "wazuh": connect((x, bot[1]), (wazuh_x, wazuh_top[1]), color=WAZUH_C, lw=1.8)
    elif tech == "elk": connect((x, bot[1]), (elk_x, elk_top[1]), color=ELK_C, lw=1.8)
    elif tech == "both":
        connect((x, bot[1]), (wazuh_x, wazuh_top[1]), color="#5B3A8E", lw=2.0, ls="dashed")
        connect((x, bot[1]), (elk_x, elk_top[1]), color="#5B3A8E", lw=2.0, ls="dashed")
compl_nmap_xy = (wazuh_x-3.6, Y_COMPL+0.6); compl_vt_xy = (wazuh_x-3.6, Y_COMPL-0.55)
ntop, nbot, nleft, nright = node(compl_nmap_xy[0], compl_nmap_xy[1], 1.9, 0.6, "nmap", NMAP_C, 10.5, edgecolor=NMAP_C, ls="dashed")
vtop, vbot, vleft, vright = node(compl_vt_xy[0], compl_vt_xy[1], 1.9, 0.6, "VirusTotal", VT_C, 10.5, edgecolor=VT_C, ls="dashed")
connect(nright, wazuh_left, color=NMAP_C, lw=2.2, ls="dashed")
connect(vright, wazuh_left, color=VT_C, lw=2.2, ls="dashed")
nmap_leaf_xs = [r[0] for r in leaf_records if r[2] == "compl-nmap"]
vt_leaf_xs = [r[0] for r in leaf_records if r[2] == "compl-vt"]
for x in nmap_leaf_xs: connect((x, Y_LEAF-LEAF_H/2-PAD*0.5), ntop, color=NMAP_C, lw=1.8, ls="dashed")
for x in vt_leaf_xs: connect((x, Y_LEAF-LEAF_H/2-PAD*0.5), vtop, color=VT_C, lw=1.8, ls="dashed")
ax.text(compl_nmap_xy[0], Y_COMPL-1.15, "Briques complementaires\n(couplees a Wazuh, jamais integrees nativement)", ha="center", va="center", fontsize=9.3, style="italic", color=NMAP_C)
ax.text((wazuh_x+elk_x)/2, Y_TECH-1.2, "Couplage possible\n(bascule de donnees)", ha="center", va="center", fontsize=9, style="italic", color="#5B3A8E")
legend_handles = [Patch(facecolor=DONE, edgecolor="#222222", label="Operationnel (deja construit et verifie)"),
                   Patch(facecolor=VERIF, edgecolor="#222222", label="Construit, a verifier (job ecrit, jamais teste en reel)"),
                   Patch(facecolor=TODO, edgecolor="#222222", label="A construire (chantier identifie, pas encore livre)"),
                   Patch(facecolor=COMPL_C, edgecolor=COMPL_C, label="Brique complementaire (couplage externe a Wazuh)")]
leg = ax.legend(handles=legend_handles, loc="lower center", bbox_to_anchor=(0.5, -0.03), ncol=2, frameon=True, fontsize=10.5, edgecolor="#8896A6", facecolor="white", framealpha=1)
leg.get_frame().set_linewidth(1.2)
ax.set_ylim(min(0, Y_COMPL-2.0), total_h)
plt.tight_layout()
plt.savefig("C:/Users/HP PROBOOK/Documents/WEF/img_arborescence.png", dpi=200, facecolor="white", bbox_inches="tight")
plt.close()
print("3/3 arborescence OK")
