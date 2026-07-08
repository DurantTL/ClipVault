import SwiftUI
struct ClipGridView: View { @ObservedObject var vm: LibraryViewModel; let cols = [GridItem(.adaptive(minimum:180), spacing:16)]
 var body: some View { ScrollView { LazyVGrid(columns:cols, spacing:16){ ForEach(vm.filteredClips){ clip in ClipCardView(clip:clip, selected: vm.selectedClipID == clip.id).onTapGesture{vm.selectedClipID=clip.id}.onTapGesture(count:2){vm.previewClip=clip}.draggable(clip) } }.padding() }.focusable().onDeleteCommand { vm.setStatus(.reject) } } }
