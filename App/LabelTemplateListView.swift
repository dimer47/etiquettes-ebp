import SwiftUI

/// Cache de miniatures de MODÈLES, rendu à la demande et idempotent par clé (même pattern
/// anti-spinner que l'écran Présentation). Une clé = modèle + taille + largeur + signature
/// de l'étiquette source. Le rendu UIKit se fait sur le MainActor, toujours terminal.
@MainActor
final class TemplateThumbnailStore: ObservableObject {
    @Published private(set) var images: [String: UIImage] = [:]
    @Published private(set) var failed: Set<String> = []

    /// Clé idempotente : identité + taille + largeur + signature de l'étiquette source + signature
    /// du contenu du modèle (`LabelTemplate.thumbnailKey`). Un changement d'étiquette OU de modèle
    /// (contenu, style, préfixe/suffixe, placeholder, mode QR) renouvelle la clé → le `.task(id:)`
    /// se relance et les anciennes entrées deviennent inertes. Plus de `reset` impératif qui
    /// effaçait les tuiles concurrentes (spinner figé déjà rencontré).
    nonisolated static func key(label: ProductLabel, template: LabelTemplate, size: LabelSize, width: Int) -> String {
        template.thumbnailKey(forLabelSignature: label.hashValue, size: size, width: width)
    }

    /// Invalide la miniature d'un modèle précis (après édition de ses zones) : les clés sont
    /// retirées du cache pour forcer un nouveau rendu à la prochaine demande.
    func invalidate(templateID: UUID) {
        images = images.filter { !$0.key.hasPrefix(templateID.uuidString) }
        failed = failed.filter { !$0.hasPrefix(templateID.uuidString) }
    }

    func thumbnail(for label: ProductLabel, template: LabelTemplate, size: LabelSize, width: Int) async {
        let key = Self.key(label: label, template: template, size: size, width: width)
        guard images[key] == nil, !failed.contains(key) else { return }
        await Task.yield()
        if Task.isCancelled { return }
        let bitmap = try? LabelRenderer.render(label, template: template, size: size, layoutWidth: width)
        let image = bitmap.flatMap(LabelRenderer.preview)
        guard images[key] == nil, !failed.contains(key) else { return }
        if let image { images[key] = image } else { failed.insert(key) }
    }
}

/// Écran « Modèles d'étiquette » : presets verrouillés (badge) + modèles perso. Chaque ligne
/// porte un mini-aperçu rendu avec le vrai moteur. Actions : nouveau, dupliquer, supprimer (perso),
/// et choix du modèle courant (coche).
struct LabelTemplateListView: View {
    @ObservedObject var store: LabelTemplateLibraryStore
    @StateObject private var thumbnails = TemplateThumbnailStore()
    /// Étiquette d'exemple pour les aperçus (produit sélectionné ou démo).
    let sampleLabel: ProductLabel
    let size: LabelSize
    let layoutWidth: Int
    /// Modèle actuellement choisi pour l'impression.
    @Binding var selectedTemplateID: UUID
    let onClose: () -> Void

    @State private var editing: LabelTemplate?
    @State private var newName = ""
    @State private var showingNew = false

    private var previewLabel: ProductLabel {
        ((try? EAN13.completed(sampleLabel.ean)) != nil &&
         PriceFormatter.formatted(sampleLabel.price, currency: sampleLabel.currency) != nil)
            ? sampleLabel : ProductLabel()
    }

    var body: some View {
        NavigationStack {
            List {
                Section(NSLocalizedString("Modèles par défaut", comment: "Preset templates section")) {
                    ForEach(LabelTemplatePresets.all) { template in row(template, locked: true) }
                }
                Section(NSLocalizedString("Mes modèles", comment: "Custom templates section")) {
                    if store.custom.isEmpty {
                        Text(NSLocalizedString("Dupliquez un modèle par défaut pour l’adapter.", comment: "No custom templates"))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(store.custom) { template in row(template, locked: false) }
                        .onDelete { indexes in
                            for index in indexes { store.delete(id: store.custom[index].id) }
                        }
                }
            }
            .navigationTitle(NSLocalizedString("Modèles", comment: "Templates screen title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString("Terminé", comment: "Done")) { onClose() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newName = ""; showingNew = true } label: {
                        Label(NSLocalizedString("Nouveau", comment: "New template"), systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editing) { template in
                LabelTemplateEditorView(store: store, thumbnails: thumbnails,
                                        template: template, sampleLabel: previewLabel,
                                        size: size, layoutWidth: layoutWidth,
                                        onSelect: { id in selectedTemplateID = id; editing = nil })
            }
            .alert(NSLocalizedString("Nouveau modèle", comment: "New template"), isPresented: $showingNew) {
                TextField(NSLocalizedString("Nom du modèle", comment: "Template name"), text: $newName)
                Button(NSLocalizedString("Créer", comment: "Create")) {
                    let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let created = store.createBlank(named: name.isEmpty ? NSLocalizedString("Mon modèle", comment: "Default new template name") : name)
                    editing = created
                }
                Button(NSLocalizedString("Annuler", comment: "Cancel"), role: .cancel) { }
            }
        }
    }

    private func row(_ template: LabelTemplate, locked: Bool) -> some View {
        let key = TemplateThumbnailStore.key(label: previewLabel, template: template, size: size, width: layoutWidth)
        let isSelected = selectedTemplateID == template.id
        return HStack(spacing: 12) {
            ZStack {
                Color.white
                if let image = thumbnails.images[key] {
                    Image(uiImage: image).interpolation(.high).resizable()
                        .aspectRatio(CGFloat(layoutWidth) / CGFloat(size.heightDots), contentMode: .fit)
                        .padding(3)
                } else if thumbnails.failed.contains(key) {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                } else {
                    ProgressView().tint(.blue)
                }
            }
            .frame(width: 92, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(.separator), lineWidth: 1))
            .task(id: key) {
                await thumbnails.thumbnail(for: previewLabel, template: template, size: size, width: layoutWidth)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(template.name).font(.headline)
                // Deux pilules jumelles : icône + texte serrés (HStack dédié, pas de Label dont
                // SwiftUI étire l'espace icône↔texte dans une largeur contrainte). « Par défaut »
                // gris, « Sélectionné » bleu. Empilées pour ne jamais se couper au milieu d'un mot.
                VStack(alignment: .leading, spacing: 4) {
                    if locked {
                        badge(NSLocalizedString("Par défaut", comment: "Default badge"),
                              systemImage: "lock.fill",
                              foreground: Color.secondary, background: Color(.tertiarySystemFill))
                    }
                    if isSelected {
                        badge(NSLocalizedString("Sélectionné", comment: "Selected badge"),
                              systemImage: "checkmark.circle.fill",
                              foreground: Color.blue, background: Color.blue.opacity(0.15))
                    }
                }
            }
            Spacer()
            Menu {
                Button { selectedTemplateID = template.id } label: {
                    Label(NSLocalizedString("Choisir ce modèle", comment: "Choose template"), systemImage: "checkmark.circle")
                }
                Button { editing = template } label: {
                    Label(locked ? NSLocalizedString("Ouvrir", comment: "Open") : NSLocalizedString("Modifier", comment: "Edit"),
                          systemImage: locked ? "eye" : "pencil")
                }
                Button {
                    if let copy = store.duplicate(id: template.id) { editing = copy }
                } label: {
                    Label(NSLocalizedString("Dupliquer", comment: "Duplicate"), systemImage: "plus.square.on.square")
                }
                if !locked {
                    Button(role: .destructive) { store.delete(id: template.id) } label: {
                        Label(NSLocalizedString("Supprimer", comment: "Delete"), systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedTemplateID = template.id }
    }

    /// Pilule « icône + libellé » serrés (spacing 4), padding et forme identiques pour les
    /// deux badges → des jumelles cohérentes, juste la couleur change.
    private func badge(_ text: String, systemImage: String,
                       foreground: Color, background: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(text).lineLimit(1)
        }
        .font(.caption2.bold())
        .foregroundStyle(foreground)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(background, in: Capsule())
    }
}
